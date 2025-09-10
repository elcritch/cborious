import ./types
import ./stream
import std/tables
import std/algorithm
import std/math
import std/typetraits
import std/enumutils


# ---- CBOR core encode/decode (ints, bools) ----

template writeInitial*(s: Stream, major: CborMajor, ai: uint8) =
  s.write(char(((uint8(major) shl 5) or (ai and 0x1f))))

# Encode unsigned integer (major type 0)
proc cborPackInt*(s: Stream, v: uint64, maj: CborMajor) =
  if v <= 23'u64:
    s.writeInitial(maj, uint8(v))
  elif v <= 0xff'u64:
    s.writeInitial(maj, 24'u8)
    s.write(char(uint8(v)))
  elif v <= 0xffff'u64:
    s.writeInitial(maj, 25'u8)
    s.store16(uint16(v))
  elif v <= 0xffff_ffff'u64:
    s.writeInitial(maj, 26'u8)
    s.store32(uint32(v))
  else:
    s.writeInitial(maj, 27'u8)
    s.store64(v)

# Public cborPack overloads
proc cborPack*(s: Stream, val: bool) =
  writeInitial(s, CborMajor.Simple, uint8(val) + 20'u8)

proc cborPackNull*(s: Stream) =
  ## Pack CBOR null (simple value 22).
  writeInitial(s, CborMajor.Simple, 22'u8)

proc cborPackUndefined*(s: Stream) =
  ## Pack CBOR undefined (simple value 23).
  writeInitial(s, CborMajor.Simple, 23'u8)

proc cborPack*(s: Stream, val: uint64) = cborPackInt(s, val, CborMajor.Unsigned)
proc cborPack*(s: Stream, val: uint32) = cborPackInt(s, uint64(val), CborMajor.Unsigned)
proc cborPack*(s: Stream, val: uint16) = cborPackInt(s, uint64(val), CborMajor.Unsigned)
proc cborPack*(s: Stream, val: uint8)  = cborPackInt(s, uint64(val), CborMajor.Unsigned)
proc cborPack*(s: Stream, val: uint)   = cborPackInt(s, uint64(val), CborMajor.Unsigned)

proc cborPack*(s: Stream, val: int64) =
  if val >= 0:
    cborPackInt(s, uint64(val), CborMajor.Unsigned)
  else:
    cborPackInt(s, uint64(-1'i64 - val), CborMajor.Negative)

proc cborPack*(s: Stream, val: int32) = cborPack(s, int64(val))
proc cborPack*(s: Stream, val: int16) = cborPack(s, int64(val))
proc cborPack*(s: Stream, val: int8)  = cborPack(s, int64(val))
proc cborPack*(s: Stream, val: int)   = cborPack(s, int64(val))


# ---- Floats (major type 7, AI 26/27) ----

template writeFloatHeader(s: Stream, ai: uint8) =
  ## Writes the initial byte for a floating-point number.
  s.writeInitial(CborMajor.Simple, ai)

proc halfToFloat32(bits: uint16): float32 =
  ## Convert IEEE-754 half-precision to float32.
  let sgn = (bits shr 15) and 0x1'u16
  let e = (bits shr 10) and 0x1F'u16
  let f = bits and 0x3FF'u16
  if e == 0x1F'u16:
    # Inf / NaN
    let sign = uint32(sgn) shl 31
    let frac32 = uint32(f) shl 13
    let exp32 = 0xFF'u32 shl 23
    return cast[float32](sign or exp32 or frac32)
  elif e == 0'u16:
    if f == 0'u16:
      # signed zero
      let sign = uint32(sgn) shl 31
      return cast[float32](sign)
    else:
      # subnormal: value = (-1)^s * f * 2^-24
      let signMul = (if sgn == 0'u16: 1.0'f32 else: -1.0'f32)
      return signMul * float32(f) * (1.0'f32 / float32(1 shl 24))
  else:
    # normal number
    let sign = uint32(sgn) shl 31
    let exp32 = uint32(uint16(e + 112'u16)) shl 23 # 127-15 = 112 bias delta
    let frac32 = uint32(f) shl 13
    return cast[float32](sign or exp32 or frac32)

proc float32ToHalfBits(v: float32): uint16 =
  ## Convert float32 to IEEE-754 half with round-to-nearest-even.
  let x = cast[uint32](v)
  let sign = (x shr 16) and 0x8000'u32
  let mant = x and 0x7fffff'u32
  let exp = (x shr 23) and 0xff'u32
  if exp == 0xff'u32: # NaN/Inf
    if mant == 0'u32: return uint16(sign or 0x7c00'u32) # Inf
    return uint16(sign or 0x7e00'u32) # qNaN canonical
  var e = int32(exp) - 127 + 15
  if e >= 31:
    return uint16(sign or 0x7c00'u32) # overflow -> Inf
  if e <= 0:
    if e < -10: return uint16(sign) # underflow -> zero
    var m = mant or 0x800000'u32
    let shift = uint32(14 - e)
    var mant2 = m shr (shift - 1)
    mant2 = mant2 + (mant2 and 1'u32) # round to even
    return uint16(sign or (mant2 shr 1))
  var mant2 = mant + 0x1000'u32 # add rounding bias
  if (mant2 and 0x800000'u32) != 0'u32:
    mant2 = 0
    inc e
  if e >= 31: return uint16(sign or 0x7c00'u32)
  return uint16(sign or (uint32(e) shl 10) or (mant2 shr 13))

proc cborPack*(s: Stream, val: float32) =
  ## Encode using minimal-size canonical: try half, else single.
  if isNaN(val):
    s.writeFloatHeader(25'u8)
    s.store16(0x7e00'u16)
    return
  if val == Inf or val == NegInf:
    s.writeFloatHeader(25'u8)
    s.store16(if val == NegInf: 0xfc00'u16 else: 0x7c00'u16)
    return
  let h = float32ToHalfBits(val)
  let back = halfToFloat32(h)
  if back == val:
    s.writeFloatHeader(25'u8)
    s.store16(h)
  else:
    s.writeFloatHeader(26'u8)
    s.store32(cast[uint32](val))

proc cborPack*(s: Stream, val: float64) =
  ## Encode using minimal-size canonical: try half, then single, else double.
  if isNaN(val):
    s.writeFloatHeader(25'u8)
    s.store16(0x7e00'u16)
    return
  if val == Inf or val == NegInf:
    s.writeFloatHeader(25'u8)
    s.store16(if val == NegInf: 0xfc00'u16 else: 0x7c00'u16)
    return
  let v32 = float32(val)
  if float64(v32) == val:
    let h = float32ToHalfBits(v32)
    if float64(halfToFloat32(h)) == val:
      s.writeFloatHeader(25'u8)
      s.store16(h)
    else:
      s.writeFloatHeader(26'u8)
      s.store32(cast[uint32](v32))
  else:
    s.writeFloatHeader(27'u8)
    s.store64(cast[uint64](val))



# ---- Decoding ----

proc readInitial*(s: Stream): tuple[major: CborMajor, ai: uint8] =
  let b = uint8(ord(s.readChar()))
  result.major = CborMajor(b shr 5)
  result.ai = b and 0x1f

proc readAddInfo*(s: Stream, ai: uint8): uint64 =
  ## Decode the additional info for integers (0..27), return value.
  if ai < 24'u8:
    result = uint64(ai)
  elif ai == 24'u8:
    result = uint64(uint8(s.readChar()))
  elif ai == 25'u8:
    result = uint64(s.unstore16())
  elif ai == 26'u8:
    result = uint64(s.unstore32())
  elif ai == 27'u8:
    result = s.unstore64()
  else:
    raise newException(CborInvalidHeaderError, "invalid integer additional info")

proc readInitialSkippingTags*(s: Stream): tuple[major: CborMajor, ai: uint8] =
  ## Reads the next initial byte, skipping one or more leading tag items.
  while true:
    let (m, ai) = s.readInitial()
    if m != CborMajor.Tag:
      return (m, ai)
    discard s.readAddInfo(ai)

proc cborUnpack*(s: Stream, val: var bool) =
  let (major, ai) = s.readInitialSkippingTags()
  if major != CborMajor.Simple:
    raise newException(CborInvalidHeaderError, "expected simple value")
  case ai
  of 20'u8: val = false
  of 21'u8: val = true
  else:
    raise newException(CborInvalidHeaderError, "expected CBOR bool")

proc cborUnpack*(s: Stream, val: var uint64) =
  let (major, ai) = s.readInitialSkippingTags()
  if major != CborMajor.Unsigned:
    raise newException(CborInvalidHeaderError, "expected unsigned integer")
  val = s.readAddInfo(ai)

proc cborUnpack*(s: Stream, val: var int64) =
  let (major, ai) = s.readInitialSkippingTags()
  case major
  of CborMajor.Unsigned:
    let u = s.readAddInfo(ai)
    if u > uint64(high(int64)):
      raise newException(CborOverflowError, "uint does not fit int64")
    val = int64(u)
  of CborMajor.Negative:
    let n = s.readAddInfo(ai)
    if n == uint64(high(uint64)):
      # can't represent - (n+1) when n == max uint64
      raise newException(CborOverflowError, "negative integer overflow")
    let tmp = int64(n)
    if tmp == high(int64):
      # would underflow; safeguard
      raise newException(CborOverflowError, "negative integer overflow")
    val = - (int64(n) + 1'i64)
  else:
    raise newException(CborInvalidHeaderError, "expected integer (major 0 or 1)")

proc cborUnpack*(s: Stream, val: var int32) =
  var x: int64
  s.cborUnpack(x)
  if x < low(int32) or x > high(int32):
    raise newException(CborOverflowError, "int32 overflow")
  val = int32(x)

proc cborUnpack*(s: Stream, val: var int16) =
  var x: int64
  s.cborUnpack(x)
  if x < low(int16) or x > high(int16):
    raise newException(CborOverflowError, "int16 overflow")
  val = int16(x)

proc cborUnpack*(s: Stream, val: var int8) =
  var x: int64
  s.cborUnpack(x)
  if x < low(int8) or x > high(int8):
    raise newException(CborOverflowError, "int8 overflow")
  val = int8(x)

proc cborUnpack*(s: Stream, val: var int) =
  when sizeof(int) == 8:
    var x64: int64
    s.cborUnpack(x64)
    val = int(x64)
  else:
    var x32: int32
    s.cborUnpack(x32)
    val = int(x32)

# ---- Float decoding ----

 

proc cborUnpack*(s: Stream, val: var float32) =
  let (major, ai) = s.readInitialSkippingTags()
  if major != CborMajor.Simple:
    raise newException(CborInvalidHeaderError, "expected simple/float value")
  case ai
  of 26'u8:
    let bits = s.unstore32()
    val = cast[float32](bits)
  of 27'u8:
    let bits = s.unstore64()
    val = float32(cast[float64](bits))
  of 25'u8:
    let bits = s.unstore16()
    val = halfToFloat32(uint16(bits))
  else:
    raise newException(CborInvalidHeaderError, "expected CBOR float (ai 25/26/27)")

proc cborUnpack*(s: Stream, val: var float64) =
  let (major, ai) = s.readInitialSkippingTags()
  if major != CborMajor.Simple:
    raise newException(CborInvalidHeaderError, "expected simple/float value")
  case ai
  of 27'u8:
    let bits = s.unstore64()
    val = cast[float64](bits)
  of 26'u8:
    let bits = s.unstore32()
    val = float64(cast[float32](bits))
  of 25'u8:
    let bits = s.unstore16()
    val = float64(halfToFloat32(uint16(bits)))
  else:
    raise newException(CborInvalidHeaderError, "expected CBOR float (ai 25/26/27)")


proc cborUnpack*(s: Stream, val: var uint32) =
  var x: uint64
  s.cborUnpack(x)
  if x > uint64(high(uint32)):
    raise newException(CborOverflowError, "uint32 overflow")
  val = uint32(x)

proc cborUnpack*(s: Stream, val: var uint16) =
  var x: uint64
  s.cborUnpack(x)
  if x > uint64(high(uint16)):
    raise newException(CborOverflowError, "uint16 overflow")
  val = uint16(x)

proc cborUnpack*(s: Stream, val: var uint8) =
  var x: uint64
  s.cborUnpack(x)
  if x > uint64(high(uint8)):
    raise newException(CborOverflowError, "uint8 overflow")
  val = uint8(x)

proc cborUnpack*(s: Stream, val: var uint) =
  when sizeof(uint) == 8:
    var x64: uint64
    s.cborUnpack(x64)
    val = uint(x64)
  else:
    var x32: uint32
    s.cborUnpack(x32)
    val = uint(x32)


# ---- Binary (byte string), Text (UTF-8 string), and Arrays ----

proc packLen(s: Stream, len: int, maj: CborMajor) {.inline.} =
  if len < 0: raise newException(CborInvalidArgError, "negative length")
  cborPackInt(s, uint64(len), maj)

# Binary (major type 2): seq/array of uint8
proc cborPack*(s: Stream, val: openArray[uint8]) =
  s.packLen(val.len, CborMajor.Binary)
  if val.len > 0:
    var i = 0
    while i < val.len:
      s.write(char(val[i]))
      inc i

proc cborPack*(s: Stream, val: seq[uint8]) = s.cborPack(val.toOpenArray(0, val.high))

# Text string (major type 3)
proc cborPack*(s: Stream, val: string) =
  s.packLen(val.len, CborMajor.String)
  if val.len > 0:
    for ch in val:
      s.write(ch)

# Array (major type 4)
proc cborPack*[T](s: Stream, val: openArray[T]) =
  s.packLen(val.len, CborMajor.Array)
  for it in val:
    s.cborPack(it)

proc cborPack*[T](s: Stream, val: seq[T]) = s.cborPack(val.toOpenArray(0, val.high))

# ---- Tags (major type 6) generic helpers ----

proc cborPackTag*(s: Stream, tag: CborTag) =
  ## Writes a CBOR tag header with the given tag value.
  cborPackInt(s, tag.uint64, CborMajor.Tag)

proc cborPackSelfDescribe*(s: Stream) =
  ## Writes the RFC 8949 §3.4.6 Self-Described CBOR tag (0xD9D9F7).
  cborPackTag(s, CborTag(SelfDescribeTagId))


# Map (major type 5)
proc cborPack*[K, V](s: Stream, val: Table[K, V]) =
  # Canonical only when using CborStream and canonicalMode is enabled
  if s of CborStream and CborStream(s).encodingMode().contains(CborCanonical):
    var items: seq[tuple[keyEnc: string, k: K, v: V]]
    items.setLen(0)
    for k, v in val.pairs:
      var ks = CborStream.init()
      ks.cborPack(k)
      items.add((move ks.data, k, v))
    items.sort(proc(a, b: typeof(items[0])): int = cmp(a.keyEnc, b.keyEnc))
    s.packLen(items.len, CborMajor.Map)
    for it in items:
      for ch in it.keyEnc: s.write(ch)
      s.cborPack(it.v)
  else:
    s.packLen(val.len, CborMajor.Map)
    for k, v in val.pairs:
      s.cborPack(k)
      s.cborPack(v)

proc cborPack*[K, V](s: Stream, val: OrderedTable[K, V]) =
  if s of CborStream and CborStream(s).encodingMode().contains(CborCanonical):
    var items: seq[tuple[keyEnc: string, k: K, v: V]]
    items.setLen(0)
    for k, v in val.pairs:
      var ks = CborStream.init()
      ks.cborPack(k)
      items.add((move ks.data, k, v))
    items.sort(proc(a, b: typeof(items[0])): int = cmp(a.keyEnc, b.keyEnc))
    s.packLen(items.len, CborMajor.Map)
    for it in items:
      for ch in it.keyEnc: s.write(ch)
      s.cborPack(it.v)
  else:
    s.packLen(val.len, CborMajor.Map)
    for k, v in val.pairs:
      s.cborPack(k)
      s.cborPack(v)


# ---- Decoding helpers ----

proc readChunk(s: Stream, majExpected: CborMajor, ai: uint8): string =
  ## Reads binary/text data handling definite and indefinite lengths.
  if ai == AiIndef:
    # Indefinite-length: concatenate definite-length chunks until break 0xff
    var acc = ""
    while true:
      let pos = s.getPosition()
      let b = s.readChar()
      if uint8(ord(b)) == 0xff'u8: # break
        break
      s.setPosition(pos)
      let (m2, ai2) = s.readInitial()
      if m2 != majExpected or ai2 == AiIndef:
        raise newException(CborInvalidHeaderError, "invalid chunk in indefinite string")
      let n = int(s.readAddInfo(ai2))
      if n < 0: raise newException(CborInvalidHeaderError, "negative length")
      let part = s.readExactStr(n)
      acc.add(part)
    return acc
  else:
    let n = int(s.readAddInfo(ai))
    if n < 0: raise newException(CborInvalidHeaderError, "negative length")
    return s.readExactStr(n)

# ---- Decoding for new types ----

proc cborUnpack*(s: Stream, val: var seq[byte]) =
  let (major, ai) = s.readInitialSkippingTags()
  if major != CborMajor.Binary:
    raise newException(CborInvalidHeaderError, "expected binary string")
  let data = s.readChunk(CborMajor.Binary, ai)
  val.setLen(data.len)
  var i = 0
  for ch in data:
    val[i] = uint8(ord(ch))
    inc i

proc cborUnpack*(s: Stream, val: var string) =
  let (major, ai) = s.readInitialSkippingTags()
  if major != CborMajor.String:
    raise newException(CborInvalidHeaderError, "expected text string")
  val = s.readChunk(CborMajor.String, ai)

proc cborUnpack*[T](s: Stream, val: var seq[T]) =
  let (major, ai) = s.readInitialSkippingTags()
  if major != CborMajor.Array:
    raise newException(CborInvalidHeaderError, "expected array")
  if ai == AiIndef:
    # Grow until break
    val.setLen(0)
    while true:
      let pos = s.getPosition()
      let b = s.readChar()
      if uint8(ord(b)) == 0xff'u8: break
      s.setPosition(pos)
      var item: T
      s.cborUnpack(item)
      val.add(item)
  else:
    let n = int(s.readAddInfo(ai))
    if n < 0: raise newException(CborInvalidHeaderError, "negative length")
    val.setLen(n)
    var i = 0
    while i < n:
      s.cborUnpack(val[i])
      inc i

type SomeMap[K, V] = Table[K, V] | OrderedTable[K, V]

proc cborUnpackImpl*[K, V](s: Stream, val: var SomeMap[K, V]) =
  let (major, ai) = s.readInitialSkippingTags()
  if major != CborMajor.Map:
    raise newException(CborInvalidHeaderError, "expected map")
  val.clear()
  if ai == AiIndef:
    while true:
      let pos = s.getPosition()
      let b = s.readChar()
      if uint8(ord(b)) == 0xff'u8: break
      s.setPosition(pos)
      var k: K
      var v: V
      s.cborUnpack(k)
      s.cborUnpack(v)
      val[k] = v
  else:
    let n = int(s.readAddInfo(ai))
    if n < 0: raise newException(CborInvalidHeaderError, "negative length")
    var i = 0
    while i < n:
      var k: K
      var v: V
      s.cborUnpack(k)
      s.cborUnpack(v)
      val[k] = v
      inc i

proc cborUnpack*[K, V](s: Stream, val: var Table[K, V]) =
  s.cborUnpackImpl(val)

proc cborUnpack*[K, V](s: Stream, val: var OrderedTable[K, V]) =
  s.cborUnpackImpl(val)


# ---- Skipping values (like msgpack4nim's skipCborMsg) ----

proc skipIndefChunks(s: Stream, majExpected: CborMajor) =
  ## Skip chunks of an indefinite-length byte/text string until break (0xff).
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
    discard s.readExactStr(n)

proc skipCborMsg*(s: Stream) =
  ## Skips over the next CBOR item, including nested arrays/maps and tags.
  let (major, ai) = s.readInitial()
  case major
  of CborMajor.Unsigned, CborMajor.Negative:
    discard s.readAddInfo(ai)
  of CborMajor.Binary, CborMajor.String:
    if ai == AiIndef:
      s.skipIndefChunks(major)
    else:
      let n = int(s.readAddInfo(ai))
      discard s.readExactStr(n)
  of CborMajor.Array:
    if ai == AiIndef:
      while true:
        let pos = s.getPosition()
        let b = s.readChar()
        if uint8(ord(b)) == 0xff'u8: break
        s.setPosition(pos)
        s.skipCborMsg()
    else:
      let n = int(s.readAddInfo(ai))
      var i = 0
      while i < n:
        s.skipCborMsg()
        inc i
  of CborMajor.Map:
    if ai == AiIndef:
      while true:
        let pos = s.getPosition()
        let b = s.readChar()
        if uint8(ord(b)) == 0xff'u8: break
        s.setPosition(pos)
        s.skipCborMsg() # key
        s.skipCborMsg() # value
    else:
      let n = int(s.readAddInfo(ai))
      var i = 0
      while i < n:
        s.skipCborMsg() # key
        s.skipCborMsg() # value
        inc i
  of CborMajor.Tag:
    discard s.readAddInfo(ai) # tag value
    s.skipCborMsg()              # skip tagged item
  of CborMajor.Simple:
    case ai
    of 24'u8: discard s.readChar()
    of 25'u8: discard s.unstore16()
    of 26'u8: discard s.unstore32()
    of 27'u8: discard s.unstore64()
    of AiIndef:
      raise newException(CborInvalidHeaderError, "unexpected break code outside indefinite")
    else:
      discard


# ---- Enums ----

{.warning[HoleEnumConv]:off.}
proc toEnum*[T: enum](val: SomeInteger): T =
  T(val)

proc allEnumValues*[T: enum](): set[T] =
  var aa: set[T]
  for x in T.items():
    aa.incl(x)
  aa

proc toEnumChecked*[T: enum](val: SomeInteger): T =
  result = T(val)
  when T is HoleyEnum:
    const anyVal = allEnumValues[T]()
    if result notin anyVal:
      raise newException(CborInvalidArgError, "invalid enum value: " & $val)

{.warning[HoleEnumConv]:on.}

proc cborPack*[T: enum](s: Stream, val: T) =
  ## Pack Nim enums; optionally as string when CborEnumAsString is enabled.
  if s of CborStream and CborEnumAsString in CborStream(s).encodingMode:
    s.cborPack($val)
  else:
    s.cborPack(int64(ord(val)))

proc cborUnpack*[T: enum](s: Stream, val: var T) =
  ## Unpack a Nim enum from either integer (ordinal) or text (name).
  let (major, ai) = s.readInitialSkippingTags()
  case major
  of CborMajor.String:
    var name: string
    # We've already consumed the initial, so read the rest of the string
    # by delegating to readChunk.
    name = s.readChunk(CborMajor.String, ai)
    var found = false
    var i = int(ord(low(T)))
    let hi = int(ord(high(T)))
    while i <= hi:
      let e =
        if s of CborStream and CborStream(s).encodingMode().contains(CborCheckHoleyEnums):
          toEnumChecked[T](i)
        else:
          toEnum[T](i)
      if $e == name:
        val = e
        found = true
        break
      inc i
    if not found:
      raise newException(CborInvalidHeaderError, "unknown enum name: " & name)
  of CborMajor.Unsigned, CborMajor.Negative:
    var tmp: int64
    # Re-interpret the current major/ai as integer additional info
    # We already consumed the initial byte above, so read the add-info value.
    block:
      var n = s.readAddInfo(ai)
      if major == CborMajor.Negative:
        if n == uint64(high(uint64)):
          raise newException(CborOverflowError, "negative integer overflow")
        tmp = - (int64(n) + 1'i64)
      else:
        tmp = int64(n)
    val = if s of CborStream and CborStream(s).encodingMode().contains(CborCheckHoleyEnums):
          toEnumChecked[T](tmp)
        else:
          toEnum[T](tmp)
  else:
    raise newException(CborInvalidHeaderError, "expected enum encoded as int or string")


# ---- Sets ----

proc cborPack*[T](s: Stream, val: set[T]) =
  ## Encode Nim sets as CBOR arrays of elements in ascending order.
  let count = val.card()
  s.packLen(count, CborMajor.Array)
  for x in items(val):
    if x in val:
      s.cborPack(x)

proc cborUnpack*[T](s: Stream, val: var set[T]) =
  ## Decode a CBOR array into a Nim set by including each element.
  let (major, ai) = s.readInitialSkippingTags()
  if major != CborMajor.Array:
    raise newException(CborInvalidHeaderError, "expected array for set")
  val = {} # clear
  if ai == AiIndef:
    while true:
      let pos = s.getPosition()
      let b = s.readChar()
      if uint8(ord(b)) == 0xff'u8: break
      s.setPosition(pos)
      var x: T
      s.cborUnpack(x)
      val.incl(x)
  else:
    let n = int(s.readAddInfo(ai))
    var i = 0
    while i < n:
      var x: T
      s.cborUnpack(x)
      val.incl(x)
      inc i
