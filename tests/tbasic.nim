import unittest
import std/tables
import cborious

proc checkPackToString[T](v: T, expected: string) =
  echo "checking " & $v & " (" & $typeof(v) & ")" & " to " & expected.repr()
  check packToString(v).repr() == expected.repr()

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
    checkPackToString(true, "\xf5")
    checkPackToString(false, "\xf4")
    checkPackToString(0'u8, "\x00")
    checkPackToString(1'u8, "\x01")
    checkPackToString(10'u8, "\x0a")
    checkPackToString(23'u8, "\x17")
    checkPackToString(24'u8, "\x18\x18")
    checkPackToString(255'u8, "\x18\xff")
    checkPackToString(256'u16, "\x19\x01\x00")
    checkPackToString(-1'i8, "\x20")
    checkPackToString(-10'i8, "\x29")
    checkPackToString(-24'i8, "\x37")
    checkPackToString(-25'i8, "\x38\x18")

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

  test "text strings (canonical + roundtrip)":
    # Canonical encodings
    check packToString("") == "\x60"
    check packToString("a") == "\x61a"
    check packToString("hello") == "\x65hello"
    var s24 = newString(24)
    for i in 0..<s24.len: s24[i] = 'a'
    check packToString(s24) == "\x78\x18" & s24
    var s255 = newString(255)
    for i in 0..<s255.len: s255[i] = 'a'
    check packToString(s255) == "\x78\xff" & s255
    var s256 = newString(256)
    for i in 0..<s256.len: s256[i] = 'a'
    check packToString(s256) == "\x79\x01\x00" & s256

    # Roundtrip
    var buf = CborStream.init()
    for s in ["", "a", "hello", s24, s255, s256]:
      buf.setPosition(0)
      pack(buf, s)
      buf.setPosition(0)
      let d = unpack(buf, string)
      check d == s

  test "binary (byte string) canonical + roundtrip":
    var bytes0 = newSeq[uint8](0)
    var bytes2 = @[0x00'u8, 0xff'u8]
    var bytes24 = newSeq[uint8](24)
    for i in 0..<bytes24.len: bytes24[i] = uint8(i)
    var bytes255 = newSeq[uint8](255)
    for i in 0..<bytes255.len: bytes255[i] = 0xAA'u8
    var bytes256 = newSeq[uint8](256)
    for i in 0..<bytes256.len: bytes256[i] = 0x55'u8

    check packToString(bytes0) == "\x40"
    check packToString(bytes2) == "\x42\x00\xff"
    block:
      var expect = "\x58\x18"
      var body = newString(bytes24.len)
      for i, v in bytes24: body[i] = char(v)
      check packToString(bytes24) == expect & body
    block:
      var expect = "\x58\xff"
      var body = newString(bytes255.len)
      for i, v in bytes255: body[i] = char(v)
      check packToString(bytes255) == expect & body
    block:
      var expect = "\x59\x01\x00"
      var body = newString(bytes256.len)
      for i, v in bytes256: body[i] = char(v)
      check packToString(bytes256) == expect & body

    # Roundtrip
    var buf = CborStream.init()
    for b in [bytes0, bytes2, bytes24, bytes255, bytes256]:
      buf.setPosition(0)
      pack(buf, b)
      buf.setPosition(0)
      let d = unpack(buf, seq[uint8])
      check d == b

  test "arrays (canonical + roundtrip)":
    # Empty
    check packToString(newSeq[int](0)) == "\x80"

    # Small array of small ints
    let arr = @[1, 2, 3]
    check packToString(arr) == "\x83\x01\x02\x03"

    # Roundtrip various arrays
    var buf = CborStream.init()
    for a in [newSeq[int](0), @[0, 23, 24, 255], @[ -1, 0, 1 ]]:
      buf.setPosition(0)
      pack(buf, a)
      buf.setPosition(0)
      let d = unpack(buf, seq[int])
      check d == a

    # Array of strings
    let sa = @["a", "", "hello"]
    buf.setPosition(0)
    pack(buf, sa)
    buf.setPosition(0)
    let sd = unpack(buf, seq[string])
    check sd == sa

  test "maps (canonical + roundtrip)":
    # Empty map canonical
    block:
      var t0 = initTable[string, int]()
      check packToString(t0) == "\xa0"

    # Single entry canonical bytes: {"a": 1}
    block:
      var t1 = initTable[string, int]()
      t1["a"] = 1
      check packToString(t1) == "\xa1\x61a\x01"

    # Roundtrip small maps
    block:
      var t2 = initTable[string, int]()
      t2["a"] = 1
      t2["b"] = 2
      var s = CborStream.init()
      pack(s, t2)
      s.setPosition(0)
      var d = unpack(s, Table[string, int])
      check d == t2

  test "maps (ordered) (canonical + roundtrip)":
    # OrderedTable roundtrip (order may change with canonical packing)
    block:
      var ot: OrderedTable[string, string]
      ot["y"] = "world"
      ot["x"] = "hello"
      var s = CborStream.init()
      pack(s, ot)
      echo "packed ", ot, " to: ", s.data.repr()
      s.setPosition(0)
      var d = unpack(s, OrderedTable[string, string])
      var tOrig = initTable[string, string]()
      for k, v in ot: tOrig[k] = v
      var tDec = initTable[string, string]()
      for k, v in d: tDec[k] = v
      check tDec == tOrig

    # Non-canonical packing via CborStream with canonical disabled preserves insertion order
    block:
      var ot2: OrderedTable[string, int]
      ot2["aa"] = 1
      ot2["b"] = 2
      var s2 = CborStream.init()
      s2.setCanonicalMode(false)
      pack(s2, ot2)
      let enc = s2.data
      # Expect order: 'aa' then 'b'
      check enc == "\xa2\x62aa\x01\x61b\x02"

  test "map canonical ordering (deterministic)":
    # String keys of different lengths: 'b' sorts before 'aa'
    block:
      var t = initTable[string, int]()
      t["aa"] = 1
      t["b"] = 2
      # Expect: A2, 61 'b', 02, 62 'a' 'a', 01
      check packToString(t) == "\xa2\x61b\x02\x62aa\x01"

    # Integer keys sort by their canonical bytes: 1 before 10
    block:
      var t2 = initTable[int, string]()
      t2[10] = "x"
      t2[1] = "y"
      # Expect: A2, 01, 61 'y', 0A, 61 'x'
      check packToString(t2) == "\xa2\x01\x61y\x0a\x61x"
