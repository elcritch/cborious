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

proc encode*(x: int8): seq[byte] =
  writer.encodeInt8(x)

proc encode*(x: int16): seq[byte] =
  writer.encodeInt16(x)

proc encode*(x: int32): seq[byte] =
  writer.encodeInt32(x)

proc encode*(x: uint8): seq[byte] =
  writer.encodeUint8(x)

proc encode*(x: uint16): seq[byte] =
  writer.encodeUint16(x)

proc encode*(x: uint32): seq[byte] =
  writer.encodeUint32(x)

proc encode*(x: uint64): seq[byte] =
  writer.encodeUint64(x)

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

# Additional specialized decode functions
proc decodeInt8*(src: openArray[byte]): int8 =
  var sdata = newString(src.len)
  for i, b in src: sdata[i] = char(b)
  let s = CborStream.init(sdata)
  let v = stream.decodeInt8(s)
  if not s.atEnd:
    raise newException(CborInvalidArgError, "extra bytes after int8")
  v

proc decodeInt16*(src: openArray[byte]): int16 =
  var sdata = newString(src.len)
  for i, b in src: sdata[i] = char(b)
  let s = CborStream.init(sdata)
  let v = stream.decodeInt16(s)
  if not s.atEnd:
    raise newException(CborInvalidArgError, "extra bytes after int16")
  v

proc decodeInt32*(src: openArray[byte]): int32 =
  var sdata = newString(src.len)
  for i, b in src: sdata[i] = char(b)
  let s = CborStream.init(sdata)
  let v = stream.decodeInt32(s)
  if not s.atEnd:
    raise newException(CborInvalidArgError, "extra bytes after int32")
  v

proc decodeUint8*(src: openArray[byte]): uint8 =
  var sdata = newString(src.len)
  for i, b in src: sdata[i] = char(b)
  let s = CborStream.init(sdata)
  let v = stream.decodeUint8(s)
  if not s.atEnd:
    raise newException(CborInvalidArgError, "extra bytes after uint8")
  v

proc decodeUint16*(src: openArray[byte]): uint16 =
  var sdata = newString(src.len)
  for i, b in src: sdata[i] = char(b)
  let s = CborStream.init(sdata)
  let v = stream.decodeUint16(s)
  if not s.atEnd:
    raise newException(CborInvalidArgError, "extra bytes after uint16")
  v

proc decodeUint32*(src: openArray[byte]): uint32 =
  var sdata = newString(src.len)
  for i, b in src: sdata[i] = char(b)
  let s = CborStream.init(sdata)
  let v = stream.decodeUint32(s)
  if not s.atEnd:
    raise newException(CborInvalidArgError, "extra bytes after uint32")
  v

proc decodeUint64*(src: openArray[byte]): uint64 =
  var sdata = newString(src.len)
  for i, b in src: sdata[i] = char(b)
  let s = CborStream.init(sdata)
  let v = stream.decodeUint64(s)
  if not s.atEnd:
    raise newException(CborInvalidArgError, "extra bytes after uint64")
  v

# Parameter-overloaded front API, msgpack4nim-style
proc encode*(dst: var seq[byte], x: int) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], x: int64) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], x: int8) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], x: int16) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], x: int32) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], x: uint8) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], x: uint16) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], x: uint32) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], x: uint64) {.inline.} = writer.encode(dst, x)
proc encode*(dst: var seq[byte], b: bool) {.inline.} = writer.encode(dst, b)

proc decode*(T: typedesc[int], src: openArray[byte]): int = decodeInt(src)
proc decode*(T: typedesc[int64], src: openArray[byte]): int64 = decodeInt64(src)
proc decode*(T: typedesc[int8], src: openArray[byte]): int8 = decodeInt8(src)
proc decode*(T: typedesc[int16], src: openArray[byte]): int16 = decodeInt16(src)
proc decode*(T: typedesc[int32], src: openArray[byte]): int32 = decodeInt32(src)
proc decode*(T: typedesc[uint8], src: openArray[byte]): uint8 = decodeUint8(src)
proc decode*(T: typedesc[uint16], src: openArray[byte]): uint16 = decodeUint16(src)
proc decode*(T: typedesc[uint32], src: openArray[byte]): uint32 = decodeUint32(src)
proc decode*(T: typedesc[uint64], src: openArray[byte]): uint64 = decodeUint64(src)
proc decode*(T: typedesc[bool], src: openArray[byte]): bool = decodeBool(src)

## Stream-based API (copied pattern from msgpack4nim)
proc encode*(s: Stream, x: int) {.inline.} = stream.encode(s, x)
proc encode*(s: Stream, x: int64) {.inline.} = stream.encode(s, x)
proc encode*(s: Stream, x: int8) {.inline.} = stream.encode(s, x)
proc encode*(s: Stream, x: int16) {.inline.} = stream.encode(s, x)
proc encode*(s: Stream, x: int32) {.inline.} = stream.encode(s, x)
proc encode*(s: Stream, x: uint8) {.inline.} = stream.encode(s, x)
proc encode*(s: Stream, x: uint16) {.inline.} = stream.encode(s, x)
proc encode*(s: Stream, x: uint32) {.inline.} = stream.encode(s, x)
proc encode*(s: Stream, x: uint64) {.inline.} = stream.encode(s, x)
proc encode*(s: Stream, b: bool) {.inline.} = stream.encode(s, b)

proc decodeInt64*(s: Stream): int64 = stream.decodeInt64(s)
proc decodeInt*(s: Stream): int = stream.decodeInt64(s).int
proc decodeInt8*(s: Stream): int8 = stream.decodeInt8(s)
proc decodeInt16*(s: Stream): int16 = stream.decodeInt16(s)
proc decodeInt32*(s: Stream): int32 = stream.decodeInt32(s)
proc decodeUint8*(s: Stream): uint8 = stream.decodeUint8(s)
proc decodeUint16*(s: Stream): uint16 = stream.decodeUint16(s)
proc decodeUint32*(s: Stream): uint32 = stream.decodeUint32(s)
proc decodeUint64*(s: Stream): uint64 = stream.decodeUint64(s)
proc decodeBool*(s: Stream): bool = stream.decodeBool(s)
