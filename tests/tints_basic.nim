import unittest
import cborious

suite "CBOR basic ints":
  test "roundtrip selected unsigned ints":
    var buf: seq[byte]
    for v in [0, 1, 23, 24, 255, 256, 65535, 65536, 4294967295'i64]:
      buf.setLen(0)
      encode(buf, int64(v))
      let dec = decode(int64, buf)
      check dec == int64(v)

  test "roundtrip selected negative ints":
    var buf: seq[byte]
    for v in [-1'i64, -10, -24, -25, -255, -256, -65535, -65536, -4294967296'i64]:
      buf.setLen(0)
      encode(buf, v)
      let dec = decode(int64, buf)
      check dec == v

  test "canonical encodings at 16/32/64-bit boundaries":
    var buf: seq[byte]
    proc encBytesI64(v: int64): seq[byte] =
      buf.setLen(0)
      encode(buf, v)
      buf
    # Unsigned thresholds
    check encBytesI64(65535)          == @[0x19'u8, 0xff'u8, 0xff'u8]
    check encBytesI64(65536)          == @[0x1a'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8]
    check encBytesI64(4294967295'i64) == @[0x1a'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8]
    check encBytesI64(4294967296'i64) == @[0x1b'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8]
    # Negative thresholds (encode n where v = -(n+1))
    check encBytesI64(-256)           == @[0x38'u8, 0xff'u8]
    check encBytesI64(-257)           == @[0x39'u8, 0x01'u8, 0x00'u8]
    check encBytesI64(-65536)         == @[0x39'u8, 0xff'u8, 0xff'u8]
    check encBytesI64(-65537)         == @[0x3a'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8]
    check encBytesI64(-4294967296'i64)== @[0x3a'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8]
    check encBytesI64(-4294967297'i64)== @[0x3b'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8]

