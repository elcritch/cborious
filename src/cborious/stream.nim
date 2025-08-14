import std/streams
import types

type
  CborStream* = ref object of StringStreamObj

{.push gcsafe.}

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

proc readExactStr*(s: Stream, length: int): string =
  ## Reads a string from a stream, raises IOError if truncated.
  result = readStr(s, length)
  if result.len != length: raise newException(IOError, "string len mismatch")

proc writeUintArg*(s: Stream, major: CborMajor, n: uint64) =
  ## Encode the CBOR header for an unsigned argument (major 0 or 1),
  ## picking the smallest-length representation.
  if n <= 23'u64:
    s.writeByte(byte((ord(major) shl 5) or int(n)))
  elif n <= 0xff'u64:
    s.writeByte(byte((ord(major) shl 5) or 24))
    s.writeByte(byte(n and 0xff'u64))
  elif n <= 0xffff'u64:
    s.writeByte(byte((ord(major) shl 5) or 25))
    s.writeByte(byte((n shr 8) and 0xff'u64))
    s.writeByte(byte(n and 0xff'u64))
  elif n <= 0xffff_ffff'u64:
    s.writeByte(byte((ord(major) shl 5) or 26))
    s.writeByte(byte((n shr 24) and 0xff'u64))
    s.writeByte(byte((n shr 16) and 0xff'u64))
    s.writeByte(byte((n shr 8) and 0xff'u64))
    s.writeByte(byte(n and 0xff'u64))
  else:
    s.writeByte(byte((ord(major) shl 5) or 27))
    s.writeByte(byte((n shr 56) and 0xff'u64))
    s.writeByte(byte((n shr 48) and 0xff'u64))
    s.writeByte(byte((n shr 40) and 0xff'u64))
    s.writeByte(byte((n shr 32) and 0xff'u64))
    s.writeByte(byte((n shr 24) and 0xff'u64))
    s.writeByte(byte((n shr 16) and 0xff'u64))
    s.writeByte(byte((n shr 8) and 0xff'u64))
    s.writeByte(byte(n and 0xff'u64))

proc encode*(s: Stream, x: int64) =
  ## Encode int64 into CBOR and write to stream.
  if x >= 0:
    s.writeUintArg(mtUnsigned, uint64(x))
  else:
    let n = uint64(-1'i64 - x)
    s.writeUintArg(mtNegative, n)

proc encode*(s: Stream, x: int) =
  s.encode(x.int64)

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
    let b0 = uint64(s.readByte())
    let b1 = uint64(s.readByte())
    return (b0 shl 8) or b1
  elif ai == 26'u8:
    if s.atEnd: raise newException(CborEndOfBufferError, "need 4 bytes")
    let b0 = uint64(s.readByte())
    let b1 = uint64(s.readByte())
    let b2 = uint64(s.readByte())
    let b3 = uint64(s.readByte())
    return (b0 shl 24) or (b1 shl 16) or (b2 shl 8) or b3
  elif ai == 27'u8:
    if s.atEnd: raise newException(CborEndOfBufferError, "need 8 bytes")
    let b0 = uint64(s.readByte())
    let b1 = uint64(s.readByte())
    let b2 = uint64(s.readByte())
    let b3 = uint64(s.readByte())
    let b4 = uint64(s.readByte())
    let b5 = uint64(s.readByte())
    let b6 = uint64(s.readByte())
    let b7 = uint64(s.readByte())
    return (b0 shl 56) or (b1 shl 48) or (b2 shl 40) or (b3 shl 32) or
           (b4 shl 24) or (b5 shl 16) or (b6 shl 8) or b7
  else:
    raise newException(CborInvalidArgError, "invalid additional info for uint argument")

proc decodeInt64*(s: Stream): int64 =
  ## Decode a CBOR integer (major 0 or 1) from the stream.
  if s.atEnd: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = s.readByte()
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  case major
  of mtUnsigned:
    let u = s.readUintArg(ai)
    return int64(u)
  of mtNegative:
    let u = s.readUintArg(ai)
    if u == high(uint64):
      raise newException(CborOverflowError, "negative int overflows int64")
    return -1'i64 - int64(u)
  else:
    raise newException(CborInvalidHeaderError, "not an integer header")

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

