import std/streams
import std/endians

export streams

type
  EncodingMode* = enum
    CborObjToArray
    CborObjToMap
    CborObjToStream
    CborCanonical
    CborEnumAsString

  CborStream* = ref object of StringStreamObj
    encodingMode: set[EncodingMode]

const defaultCborEncodingMode*: set[EncodingMode] = {CborObjToArray}

{.push gcsafe.}

# Endianness-aware utility functions (following msgpack4nim pattern)
when system.cpuEndian == littleEndian:
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
  proc store16*(s: Stream, val: uint16) = s.write(val)
  proc store32*(s: Stream, val: uint32) = s.write(val)
  proc store64*(s: Stream, val: uint64) = s.write(val)
  proc unstore16*(s: Stream): uint16 = cast[uint16](s.readInt16)
  proc unstore32*(s: Stream): uint32 = cast[uint32](s.readInt32)
  proc unstore64*(s: Stream): uint64 = cast[uint64](s.readInt64)

# Additional utility functions for different sizes (following msgpack4nim pattern)
# These are used internally and kept for potential future expansion

proc init*(x: typedesc[CborStream], data: sink string, encodingMode = defaultCborEncodingMode): CborStream =
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
  result.encodingMode = {}

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

proc encodingMode*(s: CborStream): var set[EncodingMode] =
  s.encodingMode
