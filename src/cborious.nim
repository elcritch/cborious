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
  let (v, err) = reader.decodeInt64(src, 0, consumed)
  if err != ceNone or consumed != src.len:
    raise newException(ValueError, "Invalid CBOR int64")
  v

proc decodeInt*(src: openArray[byte]): int =
  decodeInt64(src).int

proc decodeBool*(src: openArray[byte]): bool =
  var consumed = 0
  let (v, err) = reader.decodeBool(src, 0, consumed)
  if err != ceNone or consumed != src.len:
    raise newException(ValueError, "Invalid CBOR bool")
  v
