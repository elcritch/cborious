import std/streams
import cborious/stream as cstream

{.push checks: off.}

proc encodeInt64*(x: int64): seq[byte] =
  ## Encode a Nim int64 into CBOR canonical integer representation using streams.
  let s = CborStream.init()
  cstream.encode(s, x)
  s.toBytes()

proc encodeInt*(x: int): seq[byte] =
  ## Encode machine-sized int via int64 path.
  encodeInt64(x.int64)

proc encodeBool*(b: bool): seq[byte] =
  ## Encode a Nim bool into CBOR simple value true/false using streams.
  let s = CborStream.init()
  cstream.encode(s, b)
  s.toBytes()

# Additional specialized encode functions following msgpack4nim pattern
proc encodeInt8*(x: int8): seq[byte] =
  let s = CborStream.init()
  cstream.encode(s, x)
  s.toBytes()

proc encodeInt16*(x: int16): seq[byte] =
  let s = CborStream.init()
  cstream.encode(s, x)
  s.toBytes()

proc encodeInt32*(x: int32): seq[byte] =
  let s = CborStream.init()
  cstream.encode(s, x)
  s.toBytes()

proc encodeUint8*(x: uint8): seq[byte] =
  let s = CborStream.init()
  cstream.encode(s, x)
  s.toBytes()

proc encodeUint16*(x: uint16): seq[byte] =
  let s = CborStream.init()
  cstream.encode(s, x)
  s.toBytes()

proc encodeUint32*(x: uint32): seq[byte] =
  let s = CborStream.init()
  cstream.encode(s, x)
  s.toBytes()

proc encodeUint64*(x: uint64): seq[byte] =
  let s = CborStream.init()
  cstream.encode(s, x)
  s.toBytes()

# Overloaded destination-parameter style encoders (msgpack4nim-like)
proc encode*(dst: var seq[byte], x: int64) =
  let s = CborStream.init()
  cstream.encode(s, x)
  dst.add(s.toBytes())

proc encode*(dst: var seq[byte], x: int) =
  let s = CborStream.init()
  cstream.encode(s, x)
  dst.add(s.toBytes())

# Additional specialized integer encoders following msgpack4nim pattern
proc encode*(dst: var seq[byte], x: int8) =
  let s = CborStream.init()
  cstream.encode(s, x)
  dst.add(s.toBytes())

proc encode*(dst: var seq[byte], x: int16) =
  let s = CborStream.init()
  cstream.encode(s, x)
  dst.add(s.toBytes())

proc encode*(dst: var seq[byte], x: int32) =
  let s = CborStream.init()
  cstream.encode(s, x)
  dst.add(s.toBytes())

proc encode*(dst: var seq[byte], x: uint8) =
  let s = CborStream.init()
  cstream.encode(s, x)
  dst.add(s.toBytes())

proc encode*(dst: var seq[byte], x: uint16) =
  let s = CborStream.init()
  cstream.encode(s, x)
  dst.add(s.toBytes())

proc encode*(dst: var seq[byte], x: uint32) =
  let s = CborStream.init()
  cstream.encode(s, x)
  dst.add(s.toBytes())

proc encode*(dst: var seq[byte], x: uint64) =
  let s = CborStream.init()
  cstream.encode(s, x)
  dst.add(s.toBytes())

proc encode*(dst: var seq[byte], b: bool) =
  let s = CborStream.init()
  cstream.encode(s, b)
  dst.add(s.toBytes())
