import unittest
import cborious


suite "CBOR basic ints":
  test "roundtrip selected unsigned ints":
    var buf = CborStream.init()
    for v in [0, 1, 23, 24, 255, 256, 65535, 65536, 4294967295'i64]:
      buf.setPosition(0)
      pack(buf, int64(v))
      echo "packed ", v, " to: ", buf.data.repr()
      let d = unpack(buf, int64)
      check d == int64(v)

  test "roundtrip selected unsigned ints (string)":
    for v in [0, 1, 23, 24, 255, 256, 65535, 65536, 4294967295'i64]:
      var buf = pack(int64(v))
      echo "packed ", v, " to: ", buf.repr()
      let d = unpack(buf, int64)
      check d == int64(v)

  test "roundtrip selected negative ints":
    var buf = CborStream.init()
    for v in [-1'i64, -10, -24, -25, -255, -256, -65535, -65536, -4294967296'i64]:
      buf.setPosition(0)
      pack(buf, v)
      let d = unpack(buf, int64)
      check d == v

  test "canonical encodings at 16/32/64-bit boundaries":
    # Unsigned thresholds
    check pack(65535)          == "\x19\xff\xff"
    # check pack(65536)          == @[0x1a'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8]
    # check pack(4294967295'i64) == @[0x1a'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8]
    # check pack(4294967296'i64) == @[0x1b'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8]
    # # Negative thresholds (encode n where v = -(n+1))
    # check pack(-256)           == @[0x38'u8, 0xff'u8]
    # check pack(-257)           == @[0x39'u8, 0x01'u8, 0x00'u8]
    # check pack(-65536)         == @[0x39'u8, 0xff'u8, 0xff'u8]
    # check pack(-65537)         == @[0x3a'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8]
    # check pack(-4294967296'i64)== @[0x3a'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8]
    # check pack(-4294967297'i64)== @[0x3b'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8]

