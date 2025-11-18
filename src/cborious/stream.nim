import std/streams
import std/endians

# CBORious stream implementation written in nim
#
# The code in this file mostly taken from msgpack4nim, which is:
# https://github.com/Araq/msgpack4nim
#
# The license is:
#
# MessagePack implementation written in nim
#
# Copyright (c) 2015-2019 Andri Lim
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
#
#-------------------------------------

export streams

type
  EncodingMode* = enum
    CborObjToArray
    CborObjToMap
    CborObjToStream
    CborCanonical
    CborEnumAsString
    CborCheckHoleyEnums
    CborSelfDescribe

  CborStream* = ref object of StringStreamObj
    encodingMode: set[EncodingMode]

const defaultCborEncodingMode*: set[EncodingMode] = {CborObjToArray, CborCheckHoleyEnums}

{.push gcsafe.}

# Endianness-aware utility functions (following msgpack4nim pattern)
when system.cpuEndian == littleEndian:
  proc store16*(s: Stream, val: uint16 | int16) =
    var res: typeof(val)
    swapEndian16(addr(res), unsafeAddr(val))
    s.write(res)
    
  proc store32*(s: Stream, val: uint32 | int32) =
    var res: typeof(val)
    swapEndian32(addr(res), unsafeAddr(val))
    s.write(res)
    
  proc store64*(s: Stream, val: uint64 | uint64) =
    var res: typeof(val)
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

# Extended Endianness-aware utility functions
when system.cpuEndian == littleEndian:
  proc storeBE16*(s: Stream, val: uint16 | int16) =
    s.store16(val)
    
  proc storeBE32*(s: Stream, val: uint32 | int32) =
    s.store32(val)
    
  proc storeBE64*(s: Stream, val: uint64 | int64) =
    s.store64(val)
    
  proc unstoreBE16*(s: Stream): uint16 =
    s.unstore16()
    
  proc unstoreBE32*(s: Stream): uint32 =
    s.unstore32()
    
  proc unstoreBE64*(s: Stream): uint64 =
    s.unstore64()
else:
  proc storeBE16*(s: Stream, val: uint16 | int16) = s.write(val)
  proc storeBE32*(s: Stream, val: uint32 | int32) = s.write(val)
  proc storeBE64*(s: Stream, val: uint64 | int64) = s.write(val)
  proc unstoreBE16*(s: Stream): uint16 = cast[uint16](s.readInt16)
  proc unstoreBE32*(s: Stream): uint32 = cast[uint32](s.readInt32)
  proc unstoreBE64*(s: Stream): uint64 = cast[uint64](s.readInt64)

# Extended Endianness-aware utility functions
when system.cpuEndian == bigEndian:
  proc storeLE16*(s: Stream, val: uint16 | int16) =
    s.store16(val)
    
  proc storeLE32*(s: Stream, val: uint32 | int32) =
    s.store32(val)
    
  proc storeLE64*(s: Stream, val: uint64 | int64) =
    s.store64(val)
    
  proc unstoreLE16*(s: Stream): uint16 =
    s.unstore16()
    
  proc unstoreLE32*(s: Stream): uint32 =
    s.unstore32()
    
  proc unstoreLE64*(s: Stream): uint64 =
    s.unstore64()
else:
  proc storeLE16*(s: Stream, val: uint16 | int16) = s.write(val)
  proc storeLE32*(s: Stream, val: uint32 | int32) = s.write(val)
  proc storeLE64*(s: Stream, val: uint64 | int64) = s.write(val)
  proc unstoreLE16*(s: Stream): uint16 = cast[uint16](s.readInt16)
  proc unstoreLE32*(s: Stream): uint32 = cast[uint32](s.readInt32)
  proc unstoreLE64*(s: Stream): uint64 = cast[uint64](s.readInt64)

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
