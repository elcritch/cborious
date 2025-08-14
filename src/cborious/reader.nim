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

# Additional specialized decode functions following msgpack4nim pattern
proc decodeInt8*(s: Stream): int8 = cstream.decodeInt8(s)
proc decodeInt16*(s: Stream): int16 = cstream.decodeInt16(s)
proc decodeInt32*(s: Stream): int32 = cstream.decodeInt32(s)
proc decodeUint8*(s: Stream): uint8 = cstream.decodeUint8(s)
proc decodeUint16*(s: Stream): uint16 = cstream.decodeUint16(s)
proc decodeUint32*(s: Stream): uint32 = cstream.decodeUint32(s)
proc decodeUint64*(s: Stream): uint64 = cstream.decodeUint64(s)
