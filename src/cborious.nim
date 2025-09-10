# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

## Public re-exports and msgpack4nim-style API for CBOR encode/decode
import std/streams
import cborious/[types, stream, cbor, objects]

export stream, types, cbor, objects


proc unpack*[T](s: CborStream, val: var T) = s.cborUnpack(val)

proc unpack*[T](s: CborStream, val: typedesc[T]): T {.inline.} =
  unpack(s, result)

# # Generic pack wrapper matching msgpack4nim patterns
proc pack*[T](s: CborStream, val: T) =
  # Optionally emit a Self-Described CBOR tag at the start.
  if CborSelfDescribe in s.encodingMode:
    s.cborPackSelfDescribe()
  s.cborPack(val)

proc toCbor*[T](val: T, encodingMode: set[EncodingMode] = {CborObjToArray}): string =
  var s = CborStream.init(sizeof(T))
  s.encodingMode = encodingMode
  s.cborPack(val)
  result = move s.data

proc fromCbor*[T](data: sink string, val: var T, encodingMode = defaultCborEncodingMode) =
  var s = CborStream.init(data)
  s.encodingMode = encodingMode
  s.setPosition(0)
  s.unpack(val)

proc fromCbor*[T](data: sink string, val: typedesc[T], encodingMode = defaultCborEncodingMode): T =
  var s = CborStream.init(data)
  s.encodingMode = encodingMode
  s.setPosition(0)
  s.unpack(result)
