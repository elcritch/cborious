import std/json
import std/tables
import std/base64
import std/math
import std/streams

import ./types
import ./stream
import ./cbor
import ./utils

{.push gcsafe.}

proc conversionError(msg: string): ref ValueError =
  ## Local helper to mirror msgpack2json's error pattern.
  newException(ValueError, msg)

proc readIndefBreak(s: Stream): bool =
  ## Return true if the next byte is the CBOR break (0xFF); consumes it.
  let pos = s.getPosition()
  let b = s.readChar()
  if uint8(ord(b)) == 0xff'u8:
    return true
  s.setPosition(pos)
  return false

proc readChunkLocal(s: Stream, majExpected: CborMajor, ai: uint8): string =
  ## Read byte/text chunks for definite or indefinite length values.
  if ai == AiIndef:
    var acc = ""
    while true:
      let pos = s.getPosition()
      let b = s.readChar()
      if uint8(ord(b)) == 0xff'u8:
        break
      s.setPosition(pos)
      let (m2, ai2) = s.readInitial()
      if m2 != majExpected or ai2 == AiIndef:
        raise newException(CborInvalidHeaderError, "invalid chunk in indefinite item")
      let n = int(s.readAddInfo(ai2))
      if n < 0: raise newException(CborInvalidHeaderError, "negative length")
      acc.add(s.readExactStr(n))
    return acc
  else:
    let n = int(s.readAddInfo(ai))
    if n < 0: raise newException(CborInvalidHeaderError, "negative length")
    return s.readExactStr(n)

proc toJsonNode*(s: Stream): JsonNode =
  ## Convert the next CBOR item from stream `s` to a JsonNode.
  let (major, ai) = s.readInitial()
  case major
  of CborMajor.Unsigned:
    let u = s.readAddInfo(ai)
    result = newJInt(BiggestInt(u))
  of CborMajor.Negative:
    let n = s.readAddInfo(ai)
    if n > uint64(high(int64)):
      raise conversionError("CBOR negative integer out of range for JSON int")
    result = newJInt(BiggestInt(- (int64(n) + 1'i64)))
  of CborMajor.Binary:
    let raw = s.readChunkLocal(CborMajor.Binary, ai)
    let b64 = base64.encode(raw)
    result = newJObject()
    result.add("type", newJString("bin"))
    result.add("len", newJInt(BiggestInt(raw.len)))
    result.add("data", newJString(b64))
  of CborMajor.String:
    let t = s.readChunkLocal(CborMajor.String, ai)
    result = newJString(t)
  of CborMajor.Array:
    if ai == AiIndef:
      var elems: seq[JsonNode] = @[]
      while not s.readIndefBreak():
        elems.add(toJsonNode(s))
      result = JsonNode(kind: JArray)
      result.elems = move elems
    else:
      let n = int(s.readAddInfo(ai))
      if n < 0: raise conversionError("negative array length")
      result = JsonNode(kind: JArray)
      result.elems = newSeq[JsonNode](n)
      var i = 0
      while i < n:
        result.elems[i] = toJsonNode(s)
        inc i
  of CborMajor.Map:
    if ai == AiIndef:
      result = newJObject()
      while not s.readIndefBreak():
        let key = toJsonNode(s)
        if key.kind != JString:
          raise conversionError("json key needs a string")
        result[key.getStr()] = toJsonNode(s)
    else:
      let len = int(s.readAddInfo(ai))
      if len < 0: raise conversionError("negative map length")
      result = JsonNode(kind: JObject)
      result.fields = initOrderedTable[string, JsonNode](nextPowerOfTwo(len))
      var i = 0
      while i < len:
        let key = toJsonNode(s)
        if key.kind != JString:
          raise conversionError("json key needs a string")
        result.fields[key.getStr()] = toJsonNode(s)
        inc i
  of CborMajor.Tag:
    let tagVal = s.readAddInfo(ai)
    let inner = toJsonNode(s)
    result = newJObject()
    result.add("type", newJString("tag"))
    result.add("tag", newJInt(BiggestInt(tagVal)))
    result.add("value", inner)
  of CborMajor.Simple:
    case ai
    of 20'u8:
      result = newJBool(false)
    of 21'u8:
      result = newJBool(true)
    of 22'u8:
      result = newJNull()
    of 23'u8:
      # Represent undefined explicitly to preserve distinction from null
      result = newJObject()
      result.add("type", newJString("undefined"))
    of 24'u8:
      let v = uint8(s.readChar())
      let o = newJObject()
      o.add("type", newJString("simple"))
      o.add("value", newJInt(BiggestInt(v)))
      result = o
    of 25'u8:
      let bits = s.unstore16()
      result = newJFloat(halfToFloat32(bits).float)
    of 26'u8:
      let bits = s.unstore32()
      result = newJFloat(cast[float32](bits).float)
    of 27'u8:
      let bits = s.unstore64()
      result = newJFloat(cast[float64](bits))
    of AiIndef:
      raise conversionError("unexpected break code in value position")
    else:
      # Other simple values 0..19
      let o = newJObject()
      o.add("type", newJString("simple"))
      o.add("value", newJInt(BiggestInt(ai)))
      result = o
  
proc toJsonNode*(data: string): JsonNode =
  ## Convert a CBOR-encoded string `data` to a JsonNode.
  var s = CborStream.init(data)
  result = s.toJsonNode()

proc writeSimple(s: Stream, v: uint8) =
  ## Encode a CBOR simple value (excluding booleans/null/undefined/float).
  if v <= 19'u8:
    s.writeInitial(CborMajor.Simple, v)
  elif v >= 32'u8:
    s.writeInitial(CborMajor.Simple, 24'u8)
    s.write(char(v))
  else:
    # 20..23 are handled elsewhere, 24 is reserved as the marker
    raise newException(CborInvalidArgError, "invalid simple value: " & $v)

proc fromJsonNode*(s: Stream, n: JsonNode) =
  ## Encode JsonNode `n` as CBOR into stream `s`.
  case n.kind
  of JNull:
    s.cborPackNull()
  of JBool:
    s.cborPack(n.getBool())
  of JInt:
    s.cborPack(n.getInt().int64)
  of JFloat:
    s.cborPack(n.getFloat())
  of JString:
    s.cborPack(n.getStr())
  of JObject:
    # Typed objects for CBOR-specific constructs
    var tField: JsonNode = nil
    when compiles(n.hasKey("type")):
      if n.hasKey("type"): tField = n["type"]
    else:
      try:
        tField = n["type"]
      except KeyError:
        tField = nil
    if not tField.isNil and tField.kind == JString:
      let t = tField.getStr()
      case t
      of "bin":
        let dataField = n["data"]
        if dataField.isNil or dataField.kind != JString:
          raise conversionError("bin object requires string 'data'")
        let raw = base64.decode(dataField.getStr())
        var bytes = newSeq[uint8](raw.len)
        var i = 0
        for ch in raw:
          bytes[i] = uint8(ord(ch)); inc i
        s.cborPack(bytes)
      of "tag":
        let tagField = n["tag"]
        let valField = n["value"]
        if tagField.isNil or (tagField.kind != JInt and tagField.kind != JFloat):
          raise conversionError("tag object requires numeric 'tag'")
        let tagNum = (if tagField.kind == JInt: tagField.getInt().uint64
                      else: uint64(tagField.getFloat()))
        s.cborPackTag(CborTag(tagNum))
        if valField.isNil: raise conversionError("tag object missing 'value'")
        fromJsonNode(s, valField)
      of "undefined":
        s.cborPackUndefined()
      of "simple":
        let vField = n["value"]
        if vField.isNil or vField.kind != JInt:
          raise conversionError("simple object requires integer 'value'")
        let v = vField.getInt()
        if v < 0 or v > 255:
          raise conversionError("simple value out of range 0..255")
        s.writeSimple(uint8(v))
      else:
        # Unknown typed object; fall back to plain map encoding
        s.cborPackInt(uint64(n.len()), CborMajor.Map)
        for k, v in n:
          s.cborPack(k)
          fromJsonNode(s, v)
    else:
      s.cborPackInt(uint64(n.len()), CborMajor.Map)
      for k, v in n:
        s.cborPack(k)
        fromJsonNode(s, v)
  of JArray:
    s.cborPackInt(uint64(n.len()), CborMajor.Array)
    for c in n:
      fromJsonNode(s, c)

proc fromJsonNode*(n: JsonNode): string =
  ## Encode JsonNode `n` as a CBOR-encoded string buffer.
  var s = CborStream.init()
  fromJsonNode(s, n)
  result = s.data

{.pop.}
