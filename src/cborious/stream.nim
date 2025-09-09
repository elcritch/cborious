import std/streams
import std/endians
import types

export streams

type
  EncodingMode* = enum
    CBOR_OBJ_TO_DEFAULT
    CBOR_OBJ_TO_ARRAY
    CBOR_OBJ_TO_MAP
    CBOR_OBJ_TO_STREAM

  CborStream* = ref object of StringStreamObj
    encodingMode: EncodingMode
    canonicalMode: bool

{.push gcsafe.}

# Endianness-aware utility functions (following msgpack4nim pattern)
when system.cpuEndian == littleEndian:
  proc take8_8*(val: uint8): uint8 {.inline.} = val
  proc take8_16*(val: uint16): uint8 {.inline.} = uint8(val and 0xFF)
  proc take8_32*(val: uint32): uint8 {.inline.} = uint8(val and 0xFF)
  proc take8_64*(val: uint64): uint8 {.inline.} = uint8(val and 0xFF)

  proc store16*(s: Stream, val: uint16) =
    var res: uint16
    swapEndian16(addr(res), unsafeAddr(val))
    s.write(res)
    
  proc store32*(s: Stream, val: uint32) =
    var res: uint32
    swapEndian32(addr(res), unsafeAddr(val))
    s.write(res)
    
  proc store64*(s: Stream, val: uint64) =
    var res: uint64
    swapEndian64(addr(res), unsafeAddr(val))
    s.write(res)
    
  proc unstore16*(s: Stream): uint16 =
    var tmp: uint16 = cast[uint16](s.readInt16)
    swapEndian16(addr(result), addr(tmp))
    
  proc unstore32*(s: Stream): uint32 =
    var tmp: uint32 = cast[uint32](s.readInt32)
    swapEndian32(addr(result), addr(tmp))
    
  proc unstore64*(s: Stream): uint64 =
    var tmp: uint64 = cast[uint64](s.readInt64)
    swapEndian64(addr(result), addr(tmp))
else:
  proc take8_8*(val: uint8): uint8 {.inline.} = val
  proc take8_16*(val: uint16): uint8 {.inline.} = uint8((val shr 8) and 0xFF)
  proc take8_32*(val: uint32): uint8 {.inline.} = uint8((val shr 24) and 0xFF)
  proc take8_64*(val: uint64): uint8 {.inline.} = uint8((val shr 56) and 0xFF)

  proc store16*(s: Stream, val: uint16) = s.write(val)
  proc store32*(s: Stream, val: uint32) = s.write(val)
  proc store64*(s: Stream, val: uint64) = s.write(val)
  proc unstore16*(s: Stream): uint16 = cast[uint16](s.readInt16)
  proc unstore32*(s: Stream): uint32 = cast[uint32](s.readInt32)
  proc unstore64*(s: Stream): uint64 = cast[uint64](s.readInt64)

# Additional utility functions for different sizes (following msgpack4nim pattern)
# These are used internally and kept for potential future expansion

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

proc readExactStr*(s: Stream, length: int): string =
  ## Reads a string from a stream, like `Stream.readStr`, but raises IOError if it's truncated.
  result = readStr(s, length)
  if result.len != length: raise newException(IOError, "string len mismatch")

proc readExactStr*(s: Stream, length: int, str: var string) =
  ## Reads a string from a stream, like `Stream.readStr`, but raises IOError if it's truncated.
  readStr(s, length, str)
  if str.len != length: raise newException(IOError, "string len mismatch")

proc setEncodingMode*(s: CborStream, mode: EncodingMode) =
  s.encodingMode = mode

proc getEncodingMode*(s: CborStream): EncodingMode =
  s.encodingMode

proc setCanonicalMode*(s: CborStream, mode: bool) =
  s.canonicalMode = mode

proc getCanonicalMode*(s: CborStream): bool =
  s.canonicalMode