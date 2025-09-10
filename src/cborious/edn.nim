import std/strutils
import std/unicode
import std/math
import std/base64
import ./types
import ./stream
import ./cbor

type EdnError* = object of CatchableError

proc isSpace(ch: char): bool {.inline.} = ch in {' ', '\t', '\r', '\n'}

type Parser = object
  s: string
  i: int

proc initParser(s: string): Parser = Parser(s: s, i: 0)
proc atEnd(p: Parser): bool = p.i >= p.s.len
proc peek(p: Parser): char =
  if p.atEnd():
    result = '\0'
  else:
    result = p.s[p.i]

proc get(p: var Parser): char =
  let c = p.peek()
  inc p.i
  result = c

proc skipWs(p: var Parser) =
  while not p.atEnd() and isSpace(p.peek()):
    inc p.i

proc strToBytes(s: string): seq[uint8] =
  result = newSeq[uint8](s.len)
  var i = 0
  for ch in s:
    result[i] = uint8(ord(ch))
    inc i

proc decodeBase64Url(s: string): string =
  var t = newStringOfCap(s.len + 3)
  for ch in s:
    case ch
    of '-': t.add('+')
    of '_': t.add('/')
    else: t.add(ch)
  while (t.len mod 4) != 0: t.add('=')
  result = decode(t)

proc parseHexNib(ch: char): int =
  if ch >= '0' and ch <= '9': int(ord(ch) - ord('0'))
  elif ch >= 'a' and ch <= 'f': 10 + int(ord(ch) - ord('a'))
  elif ch >= 'A' and ch <= 'F': 10 + int(ord(ch) - ord('A'))
  else: -1

proc parseHexByte(p: var Parser): int =
  let h1 = parseHexNib(p.get())
  let h2 = parseHexNib(p.get())
  if h1 < 0 or h2 < 0: raise newException(EdnError, "invalid hex digit")
  (h1 shl 4) or h2

proc parseQuoted(p: var Parser): string =
  ## Parse a JSON-like quoted string with basic escapes.
  if p.get() != '"': raise newException(EdnError, "expected opening quote")
  var acc = newStringOfCap(16)
  while not p.atEnd():
    let c = p.get()
    if c == '"': return acc
    if c == '\\':
      if p.atEnd(): raise newException(EdnError, "unterminated escape")
      let e = p.get()
      case e
      of '"': acc.add('"')
      of '\\': acc.add('\\')
      of '/': acc.add('/')
      of 'b': acc.add('\b')
      of 'f': acc.add('\f')
      of 'n': acc.add('\n')
      of 'r': acc.add('\r')
      of 't': acc.add('\t')
      of 'u':
        # \uXXXX
        var code = 0
        for _ in 0..3:
          let ch = p.get()
          let v = parseHexNib(ch)
          if v < 0: raise newException(EdnError, "invalid unicode escape")
          code = (code shl 4) or v
        acc.add(Rune(code).toUTF8)
      else:
        raise newException(EdnError, "invalid escape")
    else:
      acc.add(c)
  raise newException(EdnError, "unterminated string literal")

proc parseIdent(p: var Parser): string =
  var id = newStringOfCap(8)
  while not p.atEnd():
    let c = p.peek()
    let isAlphaNum = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9')
    if isAlphaNum or c in {'.', '-', '_'}:
      id.add(c); inc p.i
    else: break
  id

proc parseNumber(p: var Parser, outFloat: var bool, fval: var float64, ival: var int64) =
  var start = p.i
  if p.peek() == '-': inc p.i
  var hasDot = false
  var hasExp = false
  while not p.atEnd():
    let c = p.peek()
    if c >= '0' and c <= '9': inc p.i
    elif c == '.' and not hasDot: hasDot = true; inc p.i
    elif (c == 'e' or c == 'E') and not hasExp:
      hasExp = true; inc p.i
      if not p.atEnd() and (p.peek() == '+' or p.peek() == '-'):
        inc p.i
    else:
      break
  let num = p.s[start..p.i-1]
  if hasDot or hasExp:
    outFloat = true
    fval = parseFloat(num)
  else:
    outFloat = false
    ival = parseInt(num)

proc expect(p: var Parser, ch: char) =
  p.skipWs()
  if p.atEnd() or p.get() != ch:
    raise newException(EdnError, "expected '" & $ch & "'")

proc parseByteStringLiteral(p: var Parser, kind: string): seq[uint8] =
  ## Parse h'..', b64'..', b64u'..', b32'..'
  if p.get() != '\'': raise newException(EdnError, "expected '")
  var buf = newStringOfCap(16)
  while not p.atEnd():
    let c = p.get()
    if c == '\'': break
    buf.add(c)
  if kind == "h":
    let s = buf.strip()
    if s.len mod 2 != 0: raise newException(EdnError, "odd-length hex")
    result = newSeqOfCap[uint8](s.len div 2)
    var i = 0
    while i < s.len:
      let h1 = parseHexNib(s[i])
      let h2 = parseHexNib(s[i+1])
      if h1 < 0 or h2 < 0: raise newException(EdnError, "invalid hex digit")
      result.add(uint8((h1 shl 4) or h2))
      inc i, 2
  elif kind == "b64":
    result = strToBytes(decode(buf))
  elif kind == "b64u":
    result = strToBytes(decodeBase64Url(buf))
  elif kind == "b32":
    # Simple base32 decoder (RFC 4648), uppercase expected; padding '=' allowed.
    const Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    var v = newSeq[int]()
    v.setLen(256)
    for i in 0..255: v[i] = -1
    for i, ch in Alphabet: v[ord(ch)] = i
    var bits = 0
    var acc = 0
    func upperAscii(ch: char): char =
      if ch >= 'a' and ch <= 'z': char(ord(ch) - 32) else: ch
    for ch in buf:
      let uch = upperAscii(ch)
      if uch == '=': break
      let val = if ord(uch) < v.len: v[ord(uch)] else: -1
      if val < 0: continue # skip whitespace or unsupported silently
      acc = (acc shl 5) or val
      bits += 5
      if bits >= 8:
        bits -= 8
        result.add(uint8((acc shr bits) and 0xff))
        # keep only the remaining lower 'bits' bits in accumulator
        if bits > 0:
          acc = acc and ((1 shl bits) - 1)
    discard
  else:
    raise newException(EdnError, "unknown bytes literal kind")

proc parseValue(p: var Parser, s: Stream)

proc parseArray(p: var Parser, s: Stream) =
  # '[' already consumed
  var items = 0
  p.skipWs()
  if not p.atEnd() and p.peek() == ']':
    cborPackInt(s, 0'u64, CborMajor.Array)
    inc p.i; return
  # Build into a temporary CborStream to count elements, then copy
  var tmp = CborStream.init()
  while true:
    p.skipWs()
    parseValue(p, tmp)
    inc items
    p.skipWs()
    if p.atEnd(): raise newException(EdnError, "unterminated array")
    let c = p.get()
    if c == ',': continue
    elif c == ']': break
    else: raise newException(EdnError, "expected ',' or ']' in array")
  cborPackInt(s, uint64(items), CborMajor.Array)
  if tmp.data.len > 0:
    for ch in tmp.data: s.write(ch)

proc parseMap(p: var Parser, s: Stream) =
  # '{' already consumed
  var pairs = 0
  p.skipWs()
  if not p.atEnd() and p.peek() == '}':
    cborPackInt(s, 0'u64, CborMajor.Map)
    inc p.i; return
  var tmp = CborStream.init()
  while true:
    p.skipWs(); parseValue(p, tmp) # key
    p.skipWs(); p.expect(':')
    p.skipWs(); parseValue(p, tmp) # value
    inc pairs
    p.skipWs()
    if p.atEnd(): raise newException(EdnError, "unterminated map")
    let c = p.get()
    if c == ',': continue
    elif c == '}': break
    else: raise newException(EdnError, "expected ',' or '}' in map")
  cborPackInt(s, uint64(pairs), CborMajor.Map)
  if tmp.data.len > 0:
    for ch in tmp.data: s.write(ch)

proc parseTag(p: var Parser, s: Stream, t: uint64) =
  p.skipWs(); p.expect('(')
  var tmp = CborStream.init()
  p.skipWs(); parseValue(p, tmp)
  p.skipWs(); p.expect(')')
  s.cborPackTag(CborTag(t))
  if tmp.data.len > 0:
    for ch in tmp.data: s.write(ch)

proc parseValue(p: var Parser, s: Stream) =
  p.skipWs()
  if p.atEnd(): raise newException(EdnError, "unexpected end")
  let c = p.peek()
  case c
  of '"':
    let t = p.parseQuoted()
    s.cborPack(t)
  of '[':
    discard p.get(); p.parseArray(s)
  of '{':
    discard p.get(); p.parseMap(s)
  of 'h':
    discard p.get(); let bs = p.parseByteStringLiteral("h")
    s.cborPack(bs)
  of 'b':
    discard p.get()
    if p.s.substr(p.i, min(p.i+2, p.s.high)) == "64'":
      inc p.i, 2
      let bs = p.parseByteStringLiteral("b64")
      s.cborPack(bs)
    elif p.s.substr(p.i, min(p.i+3, p.s.high)) == "64u'":
      inc p.i, 3
      let bs = p.parseByteStringLiteral("b64u")
      s.cborPack(bs)
    elif p.s.substr(p.i, min(p.i+2, p.s.high)) == "32'":
      inc p.i, 2
      let bs = p.parseByteStringLiteral("b32")
      s.cborPack(bs)
    else:
      raise newException(EdnError, "unknown b* bytes literal")
  of '-', '0'..'9':
    var isF: bool; var fv: float64; var iv: int64
    # Check for tag-number syntax: <digits> '(' value ')'
    if c != '-' and p.peek().isDigit():
      var j = p.i
      var t: uint64 = 0
      while j < p.s.len and p.s[j].isDigit():
        t = t * 10 + uint64(ord(p.s[j]) - ord('0'))
        inc j
      var k = j
      # allow whitespace between number and '('
      while k < p.s.len and isSpace(p.s[k]): inc k
      if k < p.s.len and p.s[k] == '(':
        # consume up to '(' and parse as tag
        p.i = k
        p.parseTag(s, t)
        return
    # Special-case -Infinity token to avoid treating as a number
    if c == '-' and not p.atEnd():
      let rest = p.s.substr(p.i, min(p.i + 8, p.s.high))
      if rest == "-Infinity":
        # consume token
        inc p.i, 9 # length of "-Infinity"
        s.cborPack(NegInf)
        return
    p.parseNumber(isF, fv, iv)
    if isF: s.cborPack(fv) else: s.cborPack(iv)
  else:
    # identifier, tag, or special
    let save = p.i
    if c.isDigit():
      var t: uint64 = 0
      while not p.atEnd() and p.peek().isDigit():
        t = t * 10 + uint64(ord(p.get()) - ord('0'))
      p.skipWs()
      if p.peek() == '(':
        p.parseTag(s, t)
        return
      else:
        raise newException(EdnError, "expected '(' after tag number")
    let id = p.parseIdent()
    case id
    of "true": s.cborPack(true)
    of "false": s.cborPack(false)
    of "null": s.cborPackNull()
    of "undefined": s.cborPackUndefined()
    of "Infinity": s.cborPack(Inf)
    of "-Infinity": s.cborPack(NegInf)
    of "NaN": s.cborPack(NaN)
    of "simple":
      p.skipWs(); p.expect('('); p.skipWs()
      var isF: bool; var fv: float64; var iv: int64
      p.parseNumber(isF, fv, iv)
      if isF or iv < 0 or iv > 255:
        raise newException(EdnError, "invalid simple() value")
      # Simple 0..23 encoded directly; 24..31 reserved; 32..255 via ai=24
      let u = uint8(iv)
      if u <= 23'u8:
        s.writeInitial(CborMajor.Simple, u)
      elif u <= 31'u8:
        raise newException(EdnError, "reserved simple value")
      else:
        s.writeInitial(CborMajor.Simple, 24'u8)
        s.write(char(u))
      p.skipWs(); p.expect(')')
    else:
      raise newException(EdnError, "unknown identifier: " & id)

proc ednToCbor*(text: string): string =
  ## Parse EDN text and return CBOR bytes.
  var p = initParser(text)
  var s = CborStream.init()
  p.parseValue(s)
  p.skipWs()
  if not p.atEnd():
    raise newException(EdnError, "trailing input after first item")
  result = move s.data

# ---- Printing CBOR -> EDN ----

proc hexEncode(data: string): string =
  const Hex = "0123456789abcdef"
  result = newStringOfCap(data.len * 2)
  for ch in data:
    let b = uint8(ord(ch))
    result.add(Hex[int(b shr 4)])
    result.add(Hex[int(b and 0x0f)])

proc printString(s: string): string =
  result = newStringOfCap(s.len + 2)
  result.add('"')
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else: result.add(c)
  result.add('"')

proc cborToEdn*(data: string): string =
  ## Convert a single CBOR item (bytes) into EDN text.
  var s = CborStream.init(data)
  s.setPosition(0)

  proc readChunkLocal(s: Stream, majExpected: CborMajor, ai: uint8): string =
    if ai == AiIndef:
      var acc = ""
      while true:
        let pos = s.getPosition()
        let b = s.readChar()
        if uint8(ord(b)) == 0xff'u8: break
        s.setPosition(pos)
        let (m2, ai2) = s.readInitial()
        if m2 != majExpected or ai2 == AiIndef:
          raise newException(EdnError, "invalid chunk in indefinite item")
        let n = int(s.readAddInfo(ai2))
        acc.add(s.readExactStr(n))
      return acc
    else:
      let n = int(s.readAddInfo(ai))
      return s.readExactStr(n)

  proc halfToFloat32Local(bits: uint16): float32 =
    let sgn = (bits shr 15) and 0x1'u16
    let e = (bits shr 10) and 0x1F'u16
    let f = bits and 0x3FF'u16
    if e == 0x1F'u16:
      let sign = uint32(sgn) shl 31
      let frac32 = uint32(f) shl 13
      let exp32 = 0xFF'u32 shl 23
      return cast[float32](sign or exp32 or frac32)
    elif e == 0'u16:
      if f == 0'u16:
        let sign = uint32(sgn) shl 31
        return cast[float32](sign)
      else:
        let signMul = (if sgn == 0'u16: 1.0'f32 else: -1.0'f32)
        return signMul * float32(f) * (1.0'f32 / float32(1 shl 24))
    else:
      let sign = uint32(sgn) shl 31
      let exp32 = uint32(uint16(e + 112'u16)) shl 23
      let frac32 = uint32(f) shl 13
      return cast[float32](sign or exp32 or frac32)

  proc go(s: Stream): string =
    let (m, ai) = s.readInitial()
    case m
    of CborMajor.Unsigned:
      $s.readAddInfo(ai)
    of CborMajor.Negative:
      let n = s.readAddInfo(ai)
      let v = - (int64(n) + 1'i64)
      $v
    of CborMajor.Binary:
      let raw = readChunkLocal(s, CborMajor.Binary, ai)
      "h'" & hexEncode(raw) & "'"
    of CborMajor.String:
      let t = readChunkLocal(s, CborMajor.String, ai)
      printString(t)
    of CborMajor.Array:
      var parts: seq[string] = @[]
      if ai == AiIndef:
        while true:
          let pos = s.getPosition()
          let b = s.readChar()
          if uint8(ord(b)) == 0xff'u8: break
          s.setPosition(pos)
          parts.add(go(s))
      else:
        let n = int(s.readAddInfo(ai))
        var i = 0
        while i < n:
          parts.add(go(s)); inc i
      "[" & parts.join(", ") & "]"
    of CborMajor.Map:
      var parts: seq[string] = @[]
      if ai == AiIndef:
        while true:
          let pos = s.getPosition()
          let b = s.readChar()
          if uint8(ord(b)) == 0xff'u8: break
          s.setPosition(pos)
          let k = go(s)
          let v = go(s)
          parts.add(k & ": " & v)
      else:
        let n = int(s.readAddInfo(ai))
        var i = 0
        while i < n:
          let k = go(s)
          let v = go(s)
          parts.add(k & ": " & v)
          inc i
      "{" & parts.join(", ") & "}"
    of CborMajor.Tag:
      let t = s.readAddInfo(ai)
      let inner = go(s)
      $t & "(" & inner & ")"
    of CborMajor.Simple:
      case ai
      of 20'u8: "true"
      of 21'u8: "false"
      of 22'u8: "null"
      of 23'u8: "undefined"
      of 24'u8:
        let v = uint8(s.readChar())
        if v <= 31'u8:
          "simple(" & $v & ")" # reserved, but render
        else:
          "simple(" & $v & ")"
      of 25'u8:
        let bits = s.unstore16()
        let f = halfToFloat32Local(bits)
        if f != f: "NaN"
        elif f == Inf: "Infinity"
        elif f == NegInf: "-Infinity"
        else: $float64(f)
      of 26'u8:
        let bits = s.unstore32()
        let f = cast[float32](bits)
        if f != f: "NaN"
        elif f == Inf: "Infinity"
        elif f == NegInf: "-Infinity"
        else: $float64(f)
      of 27'u8:
        let bits = s.unstore64()
        let f = cast[float64](bits)
        if f != f: "NaN"
        elif f == Inf: "Infinity"
        elif f == NegInf: "-Infinity"
        else: $f
      of AiIndef:
        raise newException(EdnError, "unexpected break code")
      else:
        # simple value 0..19
        "simple(" & $ai & ")"

  result = go(s)
