import types
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

# Overloaded destination-parameter style encoders (msgpack4nim-like)
proc encode*(dst: var seq[byte], x: int64) =
  let s = CborStream.init()
  cstream.encode(s, x)
  dst.add(s.toBytes())

proc encode*(dst: var seq[byte], x: int) =
  let s = CborStream.init()
  cstream.encode(s, x)
  dst.add(s.toBytes())

proc encode*(dst: var seq[byte], b: bool) =
  let s = CborStream.init()
  cstream.encode(s, b)
  dst.add(s.toBytes())
