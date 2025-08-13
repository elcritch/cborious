# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

## Public re-exports and thin API for basic CBOR encode/decode
import cborious/types
import cborious/writer
import cborious/reader

proc encode*(x: int): seq[byte] =
  encodeInt(x)

proc encode*(x: int64): seq[byte] =
  encodeInt64(x)

proc encode*(b: bool): seq[byte] =
  encodeBool(b)

proc decodeInt64*(src: openArray[byte]): int64 =
  var consumed = 0
  let v = reader.decodeInt64(src, 0, consumed)
  if consumed != src.len:
    raiseCbor(ceInvalidArg, "extra bytes after int64")
  v

proc decodeInt*(src: openArray[byte]): int =
  decodeInt64(src).int

proc decodeBool*(src: openArray[byte]): bool =
  var consumed = 0
  let v = reader.decodeBool(src, 0, consumed)
  if consumed != src.len:
    raiseCbor(ceInvalidArg, "extra bytes after bool")
  v

# Parameter-overloaded front API, msgpack4nim-style
proc encode*(dst: var seq[byte], x: int) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], x: int64) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], b: bool) {.inline.} = writer.encode(dst, b)

proc decode*(T: typedesc[int], src: openArray[byte]): int = decodeInt(src)
proc decode*(T: typedesc[int64], src: openArray[byte]): int64 = decodeInt64(src)
proc decode*(T: typedesc[bool], src: openArray[byte]): bool = decodeBool(src)
