# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

## Public re-exports and msgpack4nim-style API for CBOR encode/decode
import std/streams
import cborious/[types, stream, cbor]

export stream, types, cbor


proc pack*[T](val: T): string =
  var s = CborStream.init(sizeof(T))
  s.pack(val)
  result = s.data

proc unpack*[T](data: string, val: var T) =
  var s = CborStream.init(data)
  s.setPosition(0)
  s.unpack_type(val)

proc unpack*[StreamT, T](s: StreamT, val: var T) = s.unpack_type(val)

proc unpack*[StreamT, T](s: StreamT, val: typedesc[T]): T {.inline.} =
  unpack(s, result)

# Convenience overload to unpack directly from a string into a typedesc
proc unpack*[T](data: string, val: typedesc[T]): T {.inline.} =
  var tmp: T
  unpack(data, tmp)
  result = tmp
