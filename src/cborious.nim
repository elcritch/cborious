# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

## Public re-exports and thin API for basic CBOR encode/decode
import cborious/types
import std/streams
import cborious/writer
import cborious/reader
import cborious/stream
export stream

proc encode*(x: int): seq[byte] =
  encodeInt(x)

proc encode*(x: int64): seq[byte] =
  encodeInt64(x)

proc encode*(b: bool): seq[byte] =
  encodeBool(b)

proc decodeInt64*(src: openArray[byte]): int64 =
  var sdata = newString(src.len)
  for i, b in src: sdata[i] = char(b)
  let s = CborStream.init(sdata)
  let v = stream.decodeInt64(s)
  if not s.atEnd:
    raise newException(CborInvalidArgError, "extra bytes after int64")
  v

proc decodeInt*(src: openArray[byte]): int =
  decodeInt64(src).int

proc decodeBool*(src: openArray[byte]): bool =
  var sdata = newString(src.len)
  for i, b in src: sdata[i] = char(b)
  let s = CborStream.init(sdata)
  let v = stream.decodeBool(s)
  if not s.atEnd:
    raise newException(CborInvalidArgError, "extra bytes after bool")
  v

# Parameter-overloaded front API, msgpack4nim-style
proc encode*(dst: var seq[byte], x: int) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], x: int64) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], b: bool) {.inline.} = writer.encode(dst, b)

proc decode*(T: typedesc[int], src: openArray[byte]): int = decodeInt(src)
proc decode*(T: typedesc[int64], src: openArray[byte]): int64 = decodeInt64(src)
proc decode*(T: typedesc[bool], src: openArray[byte]): bool = decodeBool(src)

## Stream-based API (copied pattern from msgpack4nim)
proc encode*(s: Stream, x: int) {.inline.} = stream.encode(s, x)
proc encode*(s: Stream, x: int64) {.inline.} = stream.encode(s, x)
proc encode*(s: Stream, b: bool) {.inline.} = stream.encode(s, b)

proc decodeInt64*(s: Stream): int64 = stream.decodeInt64(s)
proc decodeInt*(s: Stream): int = stream.decodeInt64(s).int
proc decodeBool*(s: Stream): bool = stream.decodeBool(s)
