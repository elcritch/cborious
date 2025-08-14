import types
import std/streams
import cborious/stream as cstream

{.push checks: off.}

proc readUintArg*(s: Stream, ai: uint8): uint64 =
  ## Stream-based variant; delegates to cborious/stream.
  cstream.readUintArg(s, ai)

proc decodeInt64*(s: Stream): int64 =
  ## Decode a single CBOR integer from stream, using stream helpers.
  cstream.decodeInt64(s)

proc decodeBool*(s: Stream): bool =
  ## Decode a single CBOR boolean from stream, using stream helpers.
  cstream.decodeBool(s)
