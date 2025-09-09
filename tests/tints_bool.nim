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
    check packToString(0)    == @[0x00'u8]
    check packToString(1)    == @[0x01'u8]
    check packToString(10)   == @[0x0a'u8]
    check packToString(23)   == @[0x17'u8]
    check packToString(24)   == @[0x18'u8, 0x18'u8]
    check packToString(255)  == @[0x18'u8, 0xff'u8]
    check packToString(256)  == @[0x19'u8, 0x01'u8, 0x00'u8]
    check packToString(-1)   == @[0x20'u8]
    check packToString(-10)  == @[0x29'u8]
    check packToString(-24)  == @[0x37'u8]
    check packToString(-25)  == @[0x38'u8, 0x18'u8]
    check packToString(true) == @[0xf5'u8]
    check packToString(false)== @[0xf4'u8]
