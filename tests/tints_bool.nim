import unittest
import cborious

suite "CBOR ints and bools":
  test "roundtrip non-negative ints":
    for v in [0, 1, 10, 23, 24, 255, 256, 65535, 65536]:
      let enc = encode(v)
      let dec = decodeInt(enc)
      check dec == v

  test "roundtrip negative ints":
    for v in [-1, -10, -24, -25, -255, -256, -65535, -65536]:
      let enc = encode(v)
      let dec = decodeInt(enc)
      check dec == v

  test "bools":
    check decodeBool(encode(true)) == true
    check decodeBool(encode(false)) == false

  test "canonical encodings bytes":
    # Selected spot checks to ensure minimal-length encodings
    check encode(0) == @[0x00'u8]
    check encode(1) == @[0x01'u8]
    check encode(10) == @[0x0a'u8]
    check encode(23) == @[0x17'u8]
    check encode(24) == @[0x18'u8, 0x18'u8]
    check encode(255) == @[0x18'u8, 0xff'u8]
    check encode(256) == @[0x19'u8, 0x01'u8, 0x00'u8]
    check encode(-1) == @[0x20'u8]
    check encode(-10) == @[0x29'u8]
    check encode(-24) == @[0x37'u8]
    check encode(-25) == @[0x38'u8, 0x18'u8]
    check encode(true) == @[0xf5'u8]
    check encode(false) == @[0xf4'u8]

