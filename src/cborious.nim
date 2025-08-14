# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

## Public re-exports and msgpack4nim-style API for CBOR encode/decode
import cborious/types
import std/streams
import cborious/stream
export stream, types

# msgpack4nim-style pack function that returns seq[byte]
proc pack*[T](val: T): seq[byte] =
  let s = CborStream.init()
  s.pack(val)
  s.toBytes()

# msgpack4nim-style unpack functions
proc unpack*[T](data: openArray[byte], val: var T) =
  var sdata = newString(data.len)
  for i, b in data: sdata[i] = char(b)
  let s = CborStream.init(sdata)
  s.unpack(val)
  if not s.atEnd:
    raise newException(CborInvalidArgError, "extra bytes after value")

proc unpack*[T](data: openArray[byte], val: typedesc[T]): T =
  unpack(data, result)

# Compatibility functions for the old API style
proc encode*[T](dst: var seq[byte], val: T) =
  let encoded = pack(val)
  dst.add(encoded)

proc decode*[T](typ: typedesc[T], data: openArray[byte]): T =
  unpack(data, typ)

# Direct encoding functions for compatibility
proc encode*[T](val: T): seq[byte] = pack(val)

# Stream-based API directly from stream module  
export stream.pack, stream.unpack, stream.packType, stream.unpackType

# Re-export the stream type for direct use
export stream.CborStream
