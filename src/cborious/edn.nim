import std/math
import ./utils
import ./types
import ./stream
import ./cbor

# EDN (Extended Diagnostic Notation) pretty-printer for CBOR
# Implements a readable representation per the CBOR EDN draft:
# - Integers: decimal
# - Bools: true/false
# - Null/Undefined: null/undefined
# - Floats: decimal or special NaN/Infinity/-Infinity
# - Byte strings: h'..' (hex, lowercase)
# - Text strings: "..." (JSON-style escaping)
# - Arrays: [a, b, c]
# - Maps: {k1: v1, k2: v2}
# - Tags: n(value)

const hexDigits = "0123456789abcdef"

proc hexEncodeLower(data: string): string =
  result.setLen(data.len * 2)
  var i = 0
  for ch in data:
    let b = uint8(ord(ch))
    result[i] = hexDigits[int(b shr 4)]
    inc i
    result[i] = hexDigits[int(b and 0x0F)]
    inc i

proc quoteJsonLike(s: string): string =
  # JSON-style escaping for text strings
  result.add('"')
  for ch in s:
    case ch
    of '\\': result.add("\\\\")
    of '"':  result.add("\\\"")
    of '\b': result.add("\\b")
    of '\f': result.add("\\f")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else:
      let o = ord(ch)
      if o < 0x20:
        # Control characters -> \u00XX
        result.add("\\u00")
        result.add(hexDigits[(o shr 4) and 0xF])
        result.add(hexDigits[o and 0xF])
      else:
        result.add(ch)
  result.add('"')

proc readIndefBreak(s: Stream): bool =
  # Peek one byte; return true if it is break (0xFF). Consumes it when true.
  let pos = s.getPosition()
  let b = s.readChar()
  if uint8(ord(b)) == 0xff'u8:
    return true
  s.setPosition(pos)
  return false

proc ednFromStream*(s: Stream): string

proc ednArray(s: Stream, ai: uint8): string =
  var items: seq[string] = @[]
  if ai == AiIndef:
    while not s.readIndefBreak():
      items.add(ednFromStream(s))
  else:
    let n = int(s.readAddInfo(ai))
    var i = 0
    while i < n:
      items.add(ednFromStream(s))
      inc i
  result.add('[')
  for i, it in items:
    if i > 0: result.add(", ")
    result.add(it)
  result.add(']')

proc ednMap(s: Stream, ai: uint8): string =
  type Pair = tuple[k, v: string]
  var items: seq[Pair] = @[]
  if ai == AiIndef:
    while not s.readIndefBreak():
      let k = ednFromStream(s)
      let v = ednFromStream(s)
      items.add((k, v))
  else:
    let n = int(s.readAddInfo(ai))
    var i = 0
    while i < n:
      let k = ednFromStream(s)
      let v = ednFromStream(s)
      items.add((k, v))
      inc i
  result.add('{')
  for i, it in items:
    if i > 0: result.add(", ")
    result.add(it.k)
    result.add(": ")
    result.add(it.v)
  result.add('}')

proc readChunkLocal(s: Stream, majExpected: CborMajor, ai: uint8): string =
  ## Local copy of chunk reader for definite/indefinite byte/text strings.
  if ai == AiIndef:
    var acc = ""
    while true:
      let pos = s.getPosition()
      let b = s.readChar()
      if uint8(ord(b)) == 0xff'u8: break
      s.setPosition(pos)
      let (m2, ai2) = s.readInitial()
      if m2 != majExpected or ai2 == AiIndef:
        raise newException(CborInvalidHeaderError, "invalid chunk in indefinite string")
      let n = int(s.readAddInfo(ai2))
      let part = s.readExactStr(n)
      acc.add(part)
    return acc
  else:
    let n = int(s.readAddInfo(ai))
    return s.readExactStr(n)

proc ednBytes(s: Stream, ai: uint8): string =
  let raw = s.readChunkLocal(CborMajor.Binary, ai)
  result.add("h'")
  result.add(hexEncodeLower(raw))
  result.add("'")

proc ednText(s: Stream, ai: uint8): string =
  let t = s.readChunkLocal(CborMajor.String, ai)
  result = quoteJsonLike(t)

proc ednFloatSimple(s: Stream, ai: uint8): string =
  case ai
  of 20'u8: return "true"
  of 21'u8: return "false"
  of 22'u8: return "null"
  of 23'u8: return "undefined"
  of 24'u8:
    let v = uint8(s.readChar())
    return "simple(" & $v & ")"
  of 25'u8:
    let bits = s.unstore16()
    let f = halfToFloat32(bits)
    if isNaN(f): return "NaN"
    if f == Inf: return "Infinity"
    if f == NegInf: return "-Infinity"
    return $f
  of 26'u8:
    let bits = s.unstore32()
    let f = cast[float32](bits)
    if isNaN(f): return "NaN"
    if f == Inf: return "Infinity"
    if f == NegInf: return "-Infinity"
    return $f
  of 27'u8:
    let bits = s.unstore64()
    let f = cast[float64](bits)
    if isNaN(f): return "NaN"
    if f == Inf: return "Infinity"
    if f == NegInf: return "-Infinity"
    return $f
  of AiIndef:
    # Break code should never appear as a value here; keep defensive text
    return "simple(31)"
  else:
    # other simple values 0..19 (excluding 20..23 handled above)
    return "simple(" & $ai & ")"

proc ednFromStream*(s: Stream): string =
  let (major, ai) = s.readInitial()
  case major
  of CborMajor.Unsigned:
    let v = s.readAddInfo(ai)
    result = $v
  of CborMajor.Negative:
    let n = s.readAddInfo(ai)
    # Represent as -(n+1)
    if n == uint64(high(uint64)):
      # out-of-range, print as large negative descriptive
      result = "-" & $(int64.high) # fallback
    else:
      let v = - (int64(n) + 1'i64)
      result = $v
  of CborMajor.Binary:
    result = ednBytes(s, ai)
  of CborMajor.String:
    result = ednText(s, ai)
  of CborMajor.Array:
    result = ednArray(s, ai)
  of CborMajor.Map:
    result = ednMap(s, ai)
  of CborMajor.Tag:
    let tagVal = s.readAddInfo(ai)
    let inner = ednFromStream(s)
    result = $tagVal & "(" & inner & ")"
  of CborMajor.Simple:
    result = ednFloatSimple(s, ai)

proc ednDump*(data: sink string): string =
  ## Pretty-print a single CBOR item (encoded in `data`) as EDN.
  var s = CborStream.init(data)
  s.setPosition(0)
  result = ednFromStream(s)

proc ednDump*(s: Stream): string =
  ## Pretty-print the next CBOR item from stream `s` as EDN.
  result = ednFromStream(s)
