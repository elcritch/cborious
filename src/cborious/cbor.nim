import ./types
import ./stream

# ---- CBOR core encode/decode (ints, bools) ----

template writeInitial*(s: Stream, major: CborMajor, ai: uint8) =
  s.write(char(((uint8(major) shl 5) or (ai and 0x1f))))

# Encode unsigned integer (major type 0)
proc cborPackUInt*(s: Stream, v: uint64) =
  if v <= 23'u64:
    s.writeInitial(CborMajor.mtUnsigned, uint8(v))
  elif v <= 0xff'u64:
    s.writeInitial(CborMajor.mtUnsigned, 24'u8)
    s.write(char(uint8(v)))
  elif v <= 0xffff'u64:
    s.writeInitial(CborMajor.mtUnsigned, 25'u8)
    s.store16(uint16(v))
  elif v <= 0xffff_ffff'u64:
    s.writeInitial(CborMajor.mtUnsigned, 26'u8)
    s.store32(uint32(v))
  else:
    s.writeInitial(CborMajor.mtUnsigned, 27'u8)
    s.store64(v)

# Encode negative integer (major type 1): value is -(n+1)
proc cborPackNInt*(s: Stream, v: int64) =
  ## v must be negative
  let n = uint64(-1'i64 - v) # converts as per CBOR: encode n where v = -(n+1)
  if n <= 23'u64:
    s.writeInitial(CborMajor.mtNegative, uint8(n))
  elif n <= 0xff'u64:
    s.writeInitial(CborMajor.mtNegative, 24'u8)
    s.write(char(uint8(n)))
  elif n <= 0xffff'u64:
    s.writeInitial(CborMajor.mtNegative, 25'u8)
    s.store16(uint16(n))
  elif n <= 0xffff_ffff'u64:
    s.writeInitial(CborMajor.mtNegative, 26'u8)
    s.store32(uint32(n))
  else:
    s.writeInitial(CborMajor.mtNegative, 27'u8)
    s.store64(n)

# Public pack_type overloads
proc pack_type*(s: Stream, val: bool) =
  if val: s.write(char(0xf5'u8)) else: s.write(char(0xf4'u8))

proc pack_type*(s: Stream, val: uint64) = cborPackUInt(s, val)
proc pack_type*(s: Stream, val: uint32) = cborPackUInt(s, uint64(val))
proc pack_type*(s: Stream, val: uint16) = cborPackUInt(s, uint64(val))
proc pack_type*(s: Stream, val: uint8)  = cborPackUInt(s, uint64(val))
proc pack_type*(s: Stream, val: uint)   = cborPackUInt(s, uint64(val))

proc pack_type*(s: Stream, val: int64) =
  if val >= 0: cborPackUInt(s, uint64(val))
  else: cborPackNInt(s, val)

proc pack_type*(s: Stream, val: int32) = pack_type(s, int64(val))
proc pack_type*(s: Stream, val: int16) = pack_type(s, int64(val))
proc pack_type*(s: Stream, val: int8)  = pack_type(s, int64(val))
proc pack_type*(s: Stream, val: int)   = pack_type(s, int64(val))

# # Generic pack wrapper matching msgpack4nim patterns
# proc pack*[StreamT, T](s: StreamT, val: T) = s.pack_type(val)

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

proc unpack_type*(s: Stream, val: var bool) =
  let b = uint8(ord(s.readChar()))
  case b
  of 0xf4'u8: val = false
  of 0xf5'u8: val = true
  else:
    raise newException(CborInvalidHeaderError, "expected CBOR bool")

proc unpack_type*(s: Stream, val: var uint64) =
  let (major, ai) = s.readInitial()
  if major != CborMajor.mtUnsigned:
    raise newException(CborInvalidHeaderError, "expected unsigned integer")
  val = s.readAddInfo(ai)

proc unpack_type*(s: Stream, val: var int64) =
  let (major, ai) = s.readInitial()
  case major
  of CborMajor.mtUnsigned:
    let u = s.readAddInfo(ai)
    if u > uint64(high(int64)):
      raise newException(CborOverflowError, "uint does not fit int64")
    val = int64(u)
  of CborMajor.mtNegative:
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

proc unpack_type*(s: Stream, val: var int32) =
  var x: int64
  s.unpack_type(x)
  if x < low(int32) or x > high(int32):
    raise newException(CborOverflowError, "int32 overflow")
  val = int32(x)

proc unpack_type*(s: Stream, val: var int16) =
  var x: int64
  s.unpack_type(x)
  if x < low(int16) or x > high(int16):
    raise newException(CborOverflowError, "int16 overflow")
  val = int16(x)

proc unpack_type*(s: Stream, val: var int8) =
  var x: int64
  s.unpack_type(x)
  if x < low(int8) or x > high(int8):
    raise newException(CborOverflowError, "int8 overflow")
  val = int8(x)

proc unpack_type*(s: Stream, val: var int) =
  when sizeof(int) == 8:
    var x64: int64
    s.unpack_type(x64)
    val = int(x64)
  else:
    var x32: int32
    s.unpack_type(x32)
    val = int(x32)

proc unpack_type*(s: Stream, val: var uint32) =
  var x: uint64
  s.unpack_type(x)
  if x > uint64(high(uint32)):
    raise newException(CborOverflowError, "uint32 overflow")
  val = uint32(x)

proc unpack_type*(s: Stream, val: var uint16) =
  var x: uint64
  s.unpack_type(x)
  if x > uint64(high(uint16)):
    raise newException(CborOverflowError, "uint16 overflow")
  val = uint16(x)

proc unpack_type*(s: Stream, val: var uint8) =
  var x: uint64
  s.unpack_type(x)
  if x > uint64(high(uint8)):
    raise newException(CborOverflowError, "uint8 overflow")
  val = uint8(x)

proc unpack_type*(s: Stream, val: var uint) =
  when sizeof(uint) == 8:
    var x64: uint64
    s.unpack_type(x64)
    val = uint(x64)
  else:
    var x32: uint32
    s.unpack_type(x32)
    val = uint(x32)
