import unittest
import std/tables
import std/math
import cborious

template checkPackToString[T](v: T, expected: string) =
  echo "checking " & $v & " (" & $typeof(v) & ")" & " to " & expected.repr()
  check toCbor(v).repr() == expected.repr()

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
      var buf = toCbor(int64(v))
      echo "packed ", v, " to: ", buf.repr()
      let d = fromCbor(buf, int64)
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
    check toCbor(65535)           == "\x19\xff\xff"
    check toCbor(65536)           == "\x1a\x00\x01\x00\x00"
    check toCbor(4294967295'i64)  == "\x1a\xff\xff\xff\xff"
    check toCbor(4294967296'i64)  == "\x1b\x00\x00\x00\x01\x00\x00\x00\x00"
    # # Negative thresholds (encode n where v = -(n+1))
    check toCbor(-256)            == "\x38\xff"
    check toCbor(-257)            == "\x39\x01\x00"
    check toCbor(-65536)          == "\x39\xff\xff"
    check toCbor(-65537)          == "\x3a\x00\x01\x00\x00"
    check toCbor(-4294967296'i64) == "\x3a\xff\xff\xff\xff"
    check toCbor(-4294967297'i64) == "\x3b\x00\x00\x00\x01\x00\x00\x00\x00"

    check toCbor(-256)            == "\56\255"
    check toCbor(-257)            == "\57\1\0"
    check toCbor(-65536)          == "\57\255\255"
    check toCbor(-65537)          == "\58\0\1\0\0"
    check toCbor(-4294967296'i64) == "\58\255\255\255\255"
    check toCbor(-4294967297'i64) == "\59\0\0\0\1\0\0\0\0"

    check toCbor(65535)          == "\25\255\255"
    check toCbor(65536)          == "\26\0\1\0\0"
    check toCbor(4294967295'i64) == "\26\255\255\255\255"
    check toCbor(4294967296'i64) == "\27\0\0\0\1\0\0\0\0"


  test "text strings (canonical + roundtrip)":
    # Canonical encodings
    check toCbor("") == "\x60"
    check toCbor("a") == "\x61a"
    check toCbor("hello") == "\x65hello"
    var s24 = newString(24)
    for i in 0..<s24.len: s24[i] = 'a'
    check toCbor(s24) == "\x78\x18" & s24
    var s255 = newString(255)
    for i in 0..<s255.len: s255[i] = 'a'
    check toCbor(s255) == "\x78\xff" & s255
    var s256 = newString(256)
    for i in 0..<s256.len: s256[i] = 'a'
    check toCbor(s256) == "\x79\x01\x00" & s256

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

    check toCbor(bytes0) == "\x40"
    check toCbor(bytes2) == "\x42\x00\xff"
    block:
      var expect = "\x58\x18"
      var body = newString(bytes24.len)
      for i, v in bytes24: body[i] = char(v)
      check toCbor(bytes24) == expect & body
    block:
      var expect = "\x58\xff"
      var body = newString(bytes255.len)
      for i, v in bytes255: body[i] = char(v)
      check toCbor(bytes255) == expect & body
    block:
      var expect = "\x59\x01\x00"
      var body = newString(bytes256.len)
      for i, v in bytes256: body[i] = char(v)
      check toCbor(bytes256) == expect & body

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
    check toCbor(newSeq[int](0)) == "\x80"

    # Small array of small ints
    let arr = @[1, 2, 3]
    check toCbor(arr) == "\x83\x01\x02\x03"

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
      check toCbor(t0) == "\xa0"

    # Single entry canonical bytes: {"a": 1}
    block:
      var t1 = initTable[string, int]()
      t1["a"] = 1
      check toCbor(t1) == "\xa1\x61a\x01"

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
      s2.encodingMode().excl(CborCanonical)
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
      check toCbor(t) == "\xa2\x61b\x02\x62aa\x01"

    # Integer keys sort by their canonical bytes: 1 before 10
    block:
      var t2 = initTable[int, string]()
      t2[10] = "x"
      t2[1] = "y"
      # Expect: A2, 01, 61 'y', 0A, 61 'x'
      check toCbor(t2, {CborCanonical}) == "\xa2\x01\x61y\x0a\x61x"

  test "roundtrip float64":
    var buf = CborStream.init()
    for v in [0.0, -0.0, 1.0, -2.5, 1e-10, 1e10, Inf, NegInf]:
      buf.setPosition(0)
      pack(buf, v)
      buf.setPosition(0)
      let d = unpack(buf, float64)
      if classify(v) == fcNaN:
        check isNaN(d)
      else:
        # exact for the above values
        check d == v
    # NaN roundtrip
    block:
      var v = NaN
      buf.setPosition(0)
      pack(buf, v)
      buf.setPosition(0)
      let d = unpack(buf, float64)
      check isNaN(d)

  test "roundtrip float32":
    var buf = CborStream.init()
    for v in [0.0'f32, -0.0'f32, 1.5'f32, 3.1415927'f32, -2.5'f32]:
      buf.setPosition(0)
      pack(buf, v)
      buf.setPosition(0)
      let d = unpack(buf, float32)
      check d == v

  test "canonical encodings floats":
    # 1.5 is exactly representable as half: 0xf9 3e 00
    checkPackToString(1.5'f32, "\xf9\x3e\x00")
    checkPackToString(1.5,     "\xf9\x3e\x00")
    # -0.0 encodes as half with sign
    checkPackToString(-0.0'f32, "\xf9\x80\x00")
    checkPackToString(-0.0,     "\xf9\x80\x00")
    # Infinities encode as half
    checkPackToString(Inf,    "\xf9\x7c\x00")
    checkPackToString(NegInf, "\xf9\xfc\x00")
    # NaN encodes as canonical half NaN 0x7e00
    block:
      var n = NaN
      checkPackToString(n, "\xf9\x7e\x00")
    block:
      var n32 = float32(NaN)
      checkPackToString(n32, "\xf9\x7e\x00")

  test "skipCborMsg simple values":
    var s = CborStream.init()
    pack(s, 42)
    pack(s, "hello")
    s.setPosition(0)
    skipCborMsg(s)
    let strVal = unpack(s, string)
    check strVal == "hello"

    s = CborStream.init()
    pack(s, true)
    pack(s, 99)
    s.setPosition(0)
    skipCborMsg(s)
    let iVal = unpack(s, int)
    check iVal == 99

    s = CborStream.init()
    pack(s, 1.5)
    pack(s, 7)
    s.setPosition(0)
    skipCborMsg(s)
    let ival2 = unpack(s, int)
    check ival2 == 7

  test "skipCborMsg arrays and maps":
    var s = CborStream.init()
    pack(s, @[1,2,3])
    pack(s, 9)
    s.setPosition(0)
    skipCborMsg(s)
    check unpack(s, int) == 9

    block:
      var t = initTable[string, int]()
      t["a"] = 1
      t["b"] = 2
      var s2 = CborStream.init()
      pack(s2, t)
      pack(s2, -5)
      s2.setPosition(0)
      skipCborMsg(s2)
      check unpack(s2, int) == -5

  test "skipCborMsg tags":
    var s = CborStream.init()
    s.cborPackTag(CborTag 0'u64)
    pack(s, "t")
    pack(s, 5)
    s.setPosition(0)
    skipCborMsg(s)
    check unpack(s, int) == 5

  test "skipCborMsg indefinite strings and arrays":
    # Indefinite-length text string: 0x7f, then 'a' and 'b' chunks, break, then integer 1
    var dataTxt = "\x7f\x61a\x61b\xff\x01"
    var s1 = CborStream.init(dataTxt)
    s1.setPosition(0)
    skipCborMsg(s1)
    check unpack(s1, int) == 1

    # Indefinite-length array: 0x9f, then 1,2, break, then integer 1
    var dataArr = "\x9f\x01\x02\xff\x01"
    var s2 = CborStream.init(dataArr)
    s2.setPosition(0)
    skipCborMsg(s2)
    check unpack(s2, int) == 1

  test "enums (canonical + roundtrip)":
    type Status = enum
      stOk = 0
      stWarn = 1
      stErr = 10
      stCrit # 11

    # Canonical bytes
    check toCbor(stOk)   == "\x00"
    check toCbor(stWarn) == "\x01"
    check toCbor(stErr)  == "\x0a"
    check toCbor(stCrit) == "\x0b"

    # Roundtrip
    var s = CborStream.init()
    pack(s, stErr)
    s.setPosition(0)
    let d = unpack(s, Status)
    check d == stErr

  test "enums as string (pack + unpack)":
    type Status2 = enum
      s2Ok
      s2Warn
      s2Error
    # toCbor with enum-as-string encoding
    let enc = toCbor(s2Warn, {CborEnumAsString})
    check enc == "\x66s2Warn"
    # fromCbor accepts string encoding regardless of encoding mode
    let dec = fromCbor(enc, Status2)
    check dec == s2Warn
    # Pack via stream with enum-as-string enabled
    var cs = CborStream.init()
    cs.encodingMode = {CborEnumAsString}
    pack(cs, s2Error)
    check cs.data == "\x67s2Error"
    cs.setPosition(0)
    let d2 = unpack(cs, Status2)
    check d2 == s2Error

  test "null and undefined simple encodings":
    var s = CborStream.init()
    s.cborPackNull()
    check s.data == "\xf6"
    s = CborStream.init()
    s.cborPackUndefined()
    check s.data == "\xf7"

  test "nil seq does not encode as null and decodes to nil":
    var q: seq[int] # default-initialized (nil)
    let enc = toCbor(q)
    check enc == "\x80"
    var s = CborStream.init()
    s.cborPackNull()
    s.setPosition(0)
    var d: seq[int]
    unpack(s, d)
    # Re-encoding should produce CBOR null
    check toCbor(d) == "\x80"

  test "nil binary seq does not encode as null and decodes to nil":
    var b: seq[uint8]
    let enc = toCbor(b)
    check enc == "\x40"
    var s = CborStream.init()
    s.cborPackUndefined()
    s.setPosition(0)
    var d: seq[uint8]
    unpack(s, d)
    check toCbor(d) == "\x40"

  test "map decodes null/undefined as empty":
    var s = CborStream.init()
    s.cborPackNull()
    s.setPosition(0)
    var t = initTable[string, int]()
    s.cborUnpackImpl(t)
    check t.len == 0
    s = CborStream.init()
    s.cborPackUndefined()
    s.setPosition(0)
    s.cborUnpackImpl(t)
    check t.len == 0

suite "sets (canonical + roundtrip)":
  type Status = enum
    stOk
    stWarn
    stErr
    stCrit

  type StatusHoly = enum
    shOk = 0
    shWarn = 1
    shErr = 10
    shCrit

  test "sets cborPack and unpackCbor":
    var strm = CborStream.init()
    strm.cborPack({stOk, stErr, stCrit})
    strm.setPosition(0)
    var d0: set[Status]
    strm.cborUnpack(d0)
    check d0 == {stOk, stErr, stCrit}

  test "holy sets cborPack and unpackCbor":
    var strm = CborStream.init()
    strm.cborPack({shOk, shErr, shCrit})
    strm.setPosition(0)
    var d0: set[StatusHoly]
    strm.cborUnpack(d0)
    check d0 == {shOk, shErr, shCrit}

  test "sets toCbor and fromCbor":
    var s0: set[Status] = {}
    # empty set encodes as empty array
    check toCbor(s0) == "\x80"

    var s1: set[Status] = {stOk}
    # array(1) + 0
    check toCbor(s1) == "\x81\x00"
    let d1 = fromCbor(toCbor(s1), set[Status])
    check d1 == s1

  test "sets toCbor and fromCbor":
    var s2: set[Status] = {stCrit, stOk}
    # canonical ascending ordinals: [ord(stOk), ord(stCrit)]
    let expected = "\x82" & toCbor(stOk) & toCbor(stCrit)
    check toCbor(s2) == expected
    let d2 = fromCbor(toCbor(s2), set[Status])
    check d2 == s2

  test "sets toCbor and fromCbor":
    var s3: set[Status] = {stWarn, stErr, stCrit}
    # Construct expected via element encodings in ascending order
    let expected3 = "\x83" & toCbor(stWarn) & toCbor(stErr) & toCbor(stCrit)
    check toCbor(s3) == expected3
    let d3 = fromCbor(toCbor(s3), set[Status])
    check d3 == s3
