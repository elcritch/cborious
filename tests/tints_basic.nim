import unittest
import cborious

suite "CBOR basics":

  test "roundtrip non-negative ints":
    var buf = CborStream.init()
    for v in [0, 1, 10, 23, 24, 255, 256, 65535, 65536]:
      buf.setPosition(0)
      pack(buf, v)
      buf.setPosition(0)
      let dec = unpack(buf, int)
      check dec == v

  test "roundtrip negative ints":
    var buf = CborStream.init()
    for v in [-1, -10, -24, -25, -255, -256, -65535, -65536]:
      buf.setPosition(0)
      pack(buf, v)
      buf.setPosition(0)
      let dec = unpack(buf, int)
      check dec == v

  test "bools":
    var buf = CborStream.init()

    buf.setPosition(0)
    pack(buf, true)
    buf.setPosition(0)
    check unpack(buf, bool) == true

    buf.setPosition(0)
    pack(buf, false)
    buf.setPosition(0)
    check unpack(buf, bool) == false

  test "canonical encodings bytes":
    # Selected spot checks to ensure minimal-length encodings
    var buf = CborStream.init()
    check packToString(0)    == "\x00"
    check packToString(1)    == "\x01"
    check packToString(10)   == "\x0a"
    check packToString(23)   == "\x17"
    check packToString(24)   == "\x18\x18"
    check packToString(255)  == "\x18\xff"
    check packToString(256)  == "\x19\x01\x00"
    check packToString(-1)   == "\x20"
    check packToString(-10)  == "\x29"
    check packToString(-24)  == "\x37"
    check packToString(-25)  == "\x38\x18"
    check packToString(true) == "\xf5"
    check packToString(false)== "\xf4"
  test "roundtrip selected unsigned ints":
    var buf = CborStream.init()
    for v in [0, 1, 23, 24, 255, 256, 65535, 65536, 4294967295'i64]:
      buf.setPosition(0)
      buf.pack(int64(v))
      echo "packed ", v, " to: ", buf.data.repr()
      buf.setPosition(0)
      let d = unpack(buf, int64)
      check d == int64(v)

  test "roundtrip selected unsigned ints (string)":
    for v in [0, 1, 23, 24, 255, 256, 65535, 65536, 4294967295'i64]:
      var buf = packToString(int64(v))
      echo "packed ", v, " to: ", buf.repr()
      let d = unpackFromString(buf, int64)
      check d == int64(v)

  test "roundtrip selected negative ints":
    var buf = CborStream.init()
    for v in [-1'i64, -10, -24, -25, -255, -256, -65535, -65536, -4294967296'i64]:
      buf.setPosition(0)
      buf.pack(v)
      buf.setPosition(0)
      let d = unpack(buf, int64)
      check d == v

  test "canonical encodings at 16/32/64-bit boundaries":
    # Unsigned thresholds
    check packToString(65535)          == "\x19\xff\xff"
    check packToString(65536)          == "\x1a\x00\x01\x00\x00"
    check packToString(4294967295'i64) == "\x1a\xff\xff\xff\xff"
    check packToString(4294967296'i64) == "\x1b\x00\x00\x00\x01\x00\x00\x00\x00"
    # # Negative thresholds (encode n where v = -(n+1))
    check packToString(-256)           == "\x38\xff"
    check packToString(-257)           == "\x39\x01\x00"
    check packToString(-65536)         == "\x39\xff\xff"
    check packToString(-65537)         == "\x3a\x00\x01\x00\x00"
    check packToString(-4294967296'i64)== "\x3a\xff\xff\xff\xff"
    check packToString(-4294967297'i64)== "\x3b\x00\x00\x00\x01\x00\x00\x00\x00"

    check packToString(-256)           == "\56\255"
    check packToString(-257)           == "\57\001\000"
    check packToString(-65536)         == "\57\255\255"
    check packToString(-65537)         == "\58\000\001\000\000"
    check packToString(-4294967296'i64)== "\58\255\255\255\255"
    check packToString(-4294967297'i64)== "\59\000\000\000\001\000\000\000\000"

    check packToString(65535)          == "\25\255\255"
    check packToString(65536)          == "\26\0\1\0\0"
    check packToString(4294967295'i64) == "\26\255\255\255\255"
    check packToString(4294967296'i64) == "\27\000\000\000\001\000\000\000\000"
