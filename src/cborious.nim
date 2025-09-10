# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

## Public re-exports and msgpack4nim-style API for CBOR encode/decode
import std/streams
import cborious/[types, stream, cbor]

export stream, types, cbor


proc packToString*[T](val: T): string =
  var s = CborStream.init(sizeof(T))
  s.cborPack(val)
  result = move s.data

proc unpack*[T](s: Stream, val: var T) = s.cborUnpack(val)

proc unpack*[T](s: Stream, val: typedesc[T]): T {.inline.} =
  unpack(s, result)

# # Generic pack wrapper matching msgpack4nim patterns
proc pack*[T](s: Stream, val: T) = s.cborPack(val)

proc unpackFromString*[T](data: sink string, val: var T) =
  var s = CborStream.init(data)
  s.setPosition(0)
  s.unpack(val)

proc unpackFromString*[T](data: sink string, val: typedesc[T]): T =
  var s = CborStream.init(data)
  s.setPosition(0)
  s.unpack(result)
