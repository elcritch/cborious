import unittest
import cborious

suite "CBOR ints and bools":
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
    buf.setPosition(0);
    pack(buf, true);
    check unpack(buf, bool) == true
    buf.setPosition(0);
    pack(buf, false);
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
