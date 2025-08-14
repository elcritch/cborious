import std/streams
import std/endians
import types

type
  CborStream* = ref object of StringStreamObj

{.push gcsafe.}

# Endianness-aware utility functions (following msgpack4nim pattern)
when system.cpuEndian == littleEndian:
  proc take8_8(val: uint8): uint8 {.inline.} = val
  proc take8_16(val: uint16): uint8 {.inline.} = uint8(val and 0xFF)
  proc take8_32(val: uint32): uint8 {.inline.} = uint8(val and 0xFF)
  proc take8_64(val: uint64): uint8 {.inline.} = uint8(val and 0xFF)

  proc store16(s: Stream, val: uint16) =
    var res: uint16
    swapEndian16(addr(res), unsafeAddr(val))
    s.write(res)
    
  proc store32(s: Stream, val: uint32) =
    var res: uint32
    swapEndian32(addr(res), unsafeAddr(val))
    s.write(res)
    
  proc store64(s: Stream, val: uint64) =
    var res: uint64
    swapEndian64(addr(res), unsafeAddr(val))
    s.write(res)
    
  proc unstore16(s: Stream): uint16 =
    var tmp: uint16 = cast[uint16](s.readInt16)
    swapEndian16(addr(result), addr(tmp))
    
  proc unstore32(s: Stream): uint32 =
    var tmp: uint32 = cast[uint32](s.readInt32)
    swapEndian32(addr(result), addr(tmp))
    
  proc unstore64(s: Stream): uint64 =
    var tmp: uint64 = cast[uint64](s.readInt64)
    swapEndian64(addr(result), addr(tmp))
else:
  proc take8_8(val: uint8): uint8 {.inline.} = val
  proc take8_16(val: uint16): uint8 {.inline.} = uint8((val shr 8) and 0xFF)
  proc take8_32(val: uint32): uint8 {.inline.} = uint8((val shr 24) and 0xFF)
  proc take8_64(val: uint64): uint8 {.inline.} = uint8((val shr 56) and 0xFF)

  proc store16(s: Stream, val: uint16) = s.write(val)
  proc store32(s: Stream, val: uint32) = s.write(val)
  proc store64(s: Stream, val: uint64) = s.write(val)
  proc unstore16(s: Stream): uint16 = cast[uint16](s.readInt16)
  proc unstore32(s: Stream): uint32 = cast[uint32](s.readInt32)
  proc unstore64(s: Stream): uint64 = cast[uint64](s.readInt64)

# Additional utility functions for different sizes (following msgpack4nim pattern)
proc take8_8[T: uint8|char|int8](val: T): uint8 {.inline.} = uint8(val)
proc take16_8[T: uint8|char|int8](val: T): uint16 {.inline.} = uint16(val)
proc take32_8[T: uint8|char|int8](val: T): uint32 {.inline.} = uint32(val)
proc take64_8[T: uint8|char|int8](val: T): uint64 {.inline.} = uint64(val)

proc init*(x: typedesc[CborStream], data: sink string): CborStream =
  ## Initialize a CborStream backed by the provided string buffer.
  result = new x
  var ss = newStringStream()
  result.data = data
  result.closeImpl = ss.closeImpl
  result.atEndImpl = ss.atEndImpl
  result.setPositionImpl = ss.setPositionImpl
  result.getPositionImpl = ss.getPositionImpl
  result.readDataStrImpl = ss.readDataStrImpl
  when nimvm:
    discard
  else:
    result.readDataImpl = ss.readDataImpl
    result.peekDataImpl = ss.peekDataImpl
    result.writeDataImpl = ss.writeDataImpl

proc init*(x: typedesc[CborStream], cap: int = 0): CborStream =
  ## Initialize a CborStream with capacity.
  result = init(x, newStringOfCap(cap))

proc toBytes*(s: CborStream): seq[byte] =
  ## Return the underlying data as bytes.
  result = newSeq[byte](s.data.len)
  for i, ch in s.data:
    result[i] = byte(ch)

proc writeByte*(s: Stream, b: byte) {.inline.} =
  s.write(chr(b))

proc readByte*(s: Stream): byte {.inline.} =
  byte(s.readChar())

proc peekByte*(s: Stream): byte {.inline.} =
  byte(s.peekChar())

# Specialized encoding functions for unsigned integers (following msgpack4nim pattern)
proc encode_imp_uint8*(s: Stream, val: uint8) =
  if val <= 23'u8:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or int(val)))
  else:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or 24))
    s.writeByte(take8_8(val))

proc encode_imp_uint16*(s: Stream, val: uint16) =
  if val <= 23'u16:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or int(val)))
  elif val <= 0xff'u16:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or 24))
    s.writeByte(take8_16(val))
  else:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or 25))
    s.store16(val)

proc encode_imp_uint32*(s: Stream, val: uint32) =
  if val <= 23'u32:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or int(val)))
  elif val <= 0xff'u32:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or 24))
    s.writeByte(take8_32(val))
  elif val <= 0xffff'u32:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or 25))
    s.store16(uint16(val))
  else:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or 26))
    s.store32(val)

proc encode_imp_uint64*(s: Stream, val: uint64) =
  if val <= 23'u64:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or int(val)))
  elif val <= 0xff'u64:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or 24))
    s.writeByte(take8_64(val))
  elif val <= 0xffff'u64:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or 25))
    s.store16(uint16(val))
  elif val <= 0xffff_ffff'u64:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or 26))
    s.store32(uint32(val))
  else:
    s.writeByte(byte((ord(mtUnsigned) shl 5) or 27))
    s.store64(val)

# Specialized encoding functions for signed integers
proc encode_imp_int8*(s: Stream, val: int8) =
  if val >= 0:
    s.encode_imp_uint8(uint8(val))
  else:
    let n = uint8(-1'i8 - val)
    if n <= 23'u8:
      s.writeByte(byte((ord(mtNegative) shl 5) or int(n)))
    else:
      s.writeByte(byte((ord(mtNegative) shl 5) or 24))
      s.writeByte(take8_8(n))

proc encode_imp_int16*(s: Stream, val: int16) =
  if val >= 0:
    s.encode_imp_uint16(uint16(val))
  else:
    let n = uint16(-1'i16 - val)
    if n <= 23'u16:
      s.writeByte(byte((ord(mtNegative) shl 5) or int(n)))
    elif n <= 0xff'u16:
      s.writeByte(byte((ord(mtNegative) shl 5) or 24))
      s.writeByte(take8_16(n))
    else:
      s.writeByte(byte((ord(mtNegative) shl 5) or 25))
      s.store16(n)

proc encode_imp_int32*(s: Stream, val: int32) =
  if val >= 0:
    s.encode_imp_uint32(uint32(val))
  else:
    let n = uint32(-1'i32 - val)
    if n <= 23'u32:
      s.writeByte(byte((ord(mtNegative) shl 5) or int(n)))
    elif n <= 0xff'u32:
      s.writeByte(byte((ord(mtNegative) shl 5) or 24))
      s.writeByte(take8_32(n))
    elif n <= 0xffff'u32:
      s.writeByte(byte((ord(mtNegative) shl 5) or 25))
      s.store16(uint16(n))
    else:
      s.writeByte(byte((ord(mtNegative) shl 5) or 26))
      s.store32(n)

proc encode_imp_int64*(s: Stream, val: int64) =
  if val >= 0:
    s.encode_imp_uint64(uint64(val))
  else:
    let n = uint64(-1'i64 - val)
    if n <= 23'u64:
      s.writeByte(byte((ord(mtNegative) shl 5) or int(n)))
    elif n <= 0xff'u64:
      s.writeByte(byte((ord(mtNegative) shl 5) or 24))
      s.writeByte(take8_64(n))
    elif n <= 0xffff'u64:
      s.writeByte(byte((ord(mtNegative) shl 5) or 25))
      s.store16(uint16(n))
    elif n <= 0xffff_ffff'u64:
      s.writeByte(byte((ord(mtNegative) shl 5) or 26))
      s.store32(uint32(n))
    else:
      s.writeByte(byte((ord(mtNegative) shl 5) or 27))
      s.store64(n)

proc readExactStr*(s: Stream, length: int): string =
  ## Reads a string from a stream, raises IOError if truncated.
  result = readStr(s, length)
  if result.len != length: raise newException(IOError, "string len mismatch")

# Legacy function kept for compatibility (now uses specialized functions)
proc writeUintArg*(s: Stream, major: CborMajor, n: uint64) =
  ## Encode the CBOR header for an unsigned argument (major 0 or 1),
  ## picking the smallest-length representation.
  case major
  of mtUnsigned:
    s.encode_imp_uint64(n)
  of mtNegative:
    # For negative integers, we need to reconstruct the original negative value
    if n == high(uint64):
      raise newException(CborOverflowError, "negative int overflows int64")
    let val = -1'i64 - int64(n)
    s.encode_imp_int64(val)
  else:
    raise newException(CborInvalidArgError, "writeUintArg only supports mtUnsigned and mtNegative")

proc encode*(s: Stream, x: int64) =
  ## Encode int64 into CBOR and write to stream.
  s.encode_imp_int64(x)

proc encode*(s: Stream, x: int) =
  s.encode_imp_int64(x.int64)

# Additional overloads for specialized types following msgpack4nim pattern
proc encode*(s: Stream, x: int8) = s.encode_imp_int8(x)
proc encode*(s: Stream, x: int16) = s.encode_imp_int16(x)
proc encode*(s: Stream, x: int32) = s.encode_imp_int32(x)
proc encode*(s: Stream, x: uint8) = s.encode_imp_uint8(x)
proc encode*(s: Stream, x: uint16) = s.encode_imp_uint16(x)
proc encode*(s: Stream, x: uint32) = s.encode_imp_uint32(x)
proc encode*(s: Stream, x: uint64) = s.encode_imp_uint64(x)

proc encode*(s: Stream, b: bool) =
  s.writeByte(if b: 0xf5'u8 else: 0xf4'u8)

proc readUintArg*(s: Stream, ai: uint8): uint64 =
  ## Read the unsigned argument value according to additional info `ai`.
  if ai <= 23'u8:
    return uint64(ai)
  elif ai == 24'u8:
    if s.atEnd: raise newException(CborEndOfBufferError, "need 1 byte")
    return uint64(s.readByte())
  elif ai == 25'u8:
    if s.atEnd: raise newException(CborEndOfBufferError, "need 2 bytes")
    return uint64(s.unstore16())
  elif ai == 26'u8:
    if s.atEnd: raise newException(CborEndOfBufferError, "need 4 bytes")
    return uint64(s.unstore32())
  elif ai == 27'u8:
    if s.atEnd: raise newException(CborEndOfBufferError, "need 8 bytes")
    return s.unstore64()
  else:
    raise newException(CborInvalidArgError, "invalid additional info for uint argument")

# Specialized decoding functions for unsigned integers
proc decode_imp_uint8*(s: Stream): uint8 =
  if s.atEnd: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = s.readByte()
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  
  if major != mtUnsigned:
    raise newException(CborInvalidHeaderError, "not an unsigned integer header")
  
  let u = s.readUintArg(ai)
  if u > uint64(high(uint8)):
    raise newException(CborOverflowError, "value too large for uint8")
  result = uint8(u)

proc decode_imp_uint16*(s: Stream): uint16 =
  if s.atEnd: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = s.readByte()
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  
  if major != mtUnsigned:
    raise newException(CborInvalidHeaderError, "not an unsigned integer header")
  
  let u = s.readUintArg(ai)
  if u > uint64(high(uint16)):
    raise newException(CborOverflowError, "value too large for uint16")
  result = uint16(u)

proc decode_imp_uint32*(s: Stream): uint32 =
  if s.atEnd: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = s.readByte()
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  
  if major != mtUnsigned:
    raise newException(CborInvalidHeaderError, "not an unsigned integer header")
  
  let u = s.readUintArg(ai)
  if u > uint64(high(uint32)):
    raise newException(CborOverflowError, "value too large for uint32")
  result = uint32(u)

proc decode_imp_uint64*(s: Stream): uint64 =
  if s.atEnd: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = s.readByte()
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  
  if major != mtUnsigned:
    raise newException(CborInvalidHeaderError, "not an unsigned integer header")
  
  result = s.readUintArg(ai)

# Specialized decoding functions for signed integers
proc decode_imp_int8*(s: Stream): int8 =
  if s.atEnd: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = s.readByte()
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  
  case major
  of mtUnsigned:
    let u = s.readUintArg(ai)
    if u > uint64(high(int8)):
      raise newException(CborOverflowError, "value too large for int8")
    result = int8(u)
  of mtNegative:
    let u = s.readUintArg(ai)
    if u > uint64(high(int8)):
      raise newException(CborOverflowError, "negative value too large for int8")
    result = -1'i8 - int8(u)
  else:
    raise newException(CborInvalidHeaderError, "not an integer header")

proc decode_imp_int16*(s: Stream): int16 =
  if s.atEnd: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = s.readByte()
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  
  case major
  of mtUnsigned:
    let u = s.readUintArg(ai)
    if u > uint64(high(int16)):
      raise newException(CborOverflowError, "value too large for int16")
    result = int16(u)
  of mtNegative:
    let u = s.readUintArg(ai)
    if u > uint64(high(int16)):
      raise newException(CborOverflowError, "negative value too large for int16")
    result = -1'i16 - int16(u)
  else:
    raise newException(CborInvalidHeaderError, "not an integer header")

proc decode_imp_int32*(s: Stream): int32 =
  if s.atEnd: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = s.readByte()
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  
  case major
  of mtUnsigned:
    let u = s.readUintArg(ai)
    if u > uint64(high(int32)):
      raise newException(CborOverflowError, "value too large for int32")
    result = int32(u)
  of mtNegative:
    let u = s.readUintArg(ai)
    if u > uint64(high(int32)):
      raise newException(CborOverflowError, "negative value too large for int32")
    result = -1'i32 - int32(u)
  else:
    raise newException(CborInvalidHeaderError, "not an integer header")

proc decode_imp_int64*(s: Stream): int64 =
  if s.atEnd: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = s.readByte()
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  
  case major
  of mtUnsigned:
    let u = s.readUintArg(ai)
    if u > uint64(high(int64)):
      raise newException(CborOverflowError, "value too large for int64")
    result = int64(u)
  of mtNegative:
    let u = s.readUintArg(ai)
    if u == high(uint64):
      raise newException(CborOverflowError, "negative int overflows int64")
    result = -1'i64 - int64(u)
  else:
    raise newException(CborInvalidHeaderError, "not an integer header")

proc decodeInt64*(s: Stream): int64 =
  ## Decode a CBOR integer (major 0 or 1) from the stream.
  s.decode_imp_int64()

# Additional decoding overloads for specialized types
proc decodeInt8*(s: Stream): int8 = s.decode_imp_int8()
proc decodeInt16*(s: Stream): int16 = s.decode_imp_int16()
proc decodeInt32*(s: Stream): int32 = s.decode_imp_int32()
proc decodeUint8*(s: Stream): uint8 = s.decode_imp_uint8()
proc decodeUint16*(s: Stream): uint16 = s.decode_imp_uint16()
proc decodeUint32*(s: Stream): uint32 = s.decode_imp_uint32()
proc decodeUint64*(s: Stream): uint64 = s.decode_imp_uint64()

proc decodeBool*(s: Stream): bool =
  ## Decode a CBOR boolean from the stream.
  if s.atEnd: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = s.readByte()
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  if major != mtSimple: raise newException(CborInvalidHeaderError, "not a simple value header")
  case ai
  of 20'u8: false
  of 21'u8: true
  else: raise newException(CborInvalidArgError, "not a bool simple value")

