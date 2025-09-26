import unittest
import std/tables
import std/json
import std/base64
import std/math

import cborious
import cborious/cbor2json

suite "cbor2json conversions":

  test "primitives roundtrip":
    var s = CborStream.init()
    # int
    s.setPosition(0)
    pack(s, 42)
    s.setPosition(0)
    let j1 = toJsonNode(s)
    check j1.kind == JInt and j1.getInt() == 42
    let enc1 = fromJsonNode(j1)
    check fromCbor(enc1, int) == 42

    # negative int
    s = CborStream.init()
    pack(s, -5)
    s.setPosition(0)
    let j2 = toJsonNode(s)
    check j2.kind == JInt and j2.getInt() == -5
    let enc2 = fromJsonNode(j2)
    check fromCbor(enc2, int) == -5

    # bool
    s = CborStream.init()
    pack(s, true)
    s.setPosition(0)
    let j3 = toJsonNode(s)
    check j3.kind == JBool and j3.getBool() == true
    let enc3 = fromJsonNode(j3)
    check fromCbor(enc3, bool) == true

    # null
    s = CborStream.init()
    s.cborPackNull()
    s.setPosition(0)
    let j4 = toJsonNode(s)
    check j4.kind == JNull
    let enc4 = fromJsonNode(j4)
    check enc4 == "\xf6"

    # undefined
    s = CborStream.init()
    s.cborPackUndefined()
    s.setPosition(0)
    let j5 = toJsonNode(s)
    check j5.kind == JNull
    let enc5 = fromJsonNode(j5)
    check enc5 == "\xf6"

  test "binary":
    var bytes = @[0x00'u8, 0xff'u8]
    var s = CborStream.init()
    pack(s, bytes)
    s.setPosition(0)
    let j = toJsonNode(s, {BinaryAsBase64})
    check j.kind == JObject
    check j["type"].getStr() == "bin"
    check j["len"].getInt().int == 2
    check j["data"].getStr() == base64.encode("\x00\xff")
    let enc = fromJsonNode(j)
    check enc == "\x42\x00\xff"

  test "tags":
    var s = CborStream.init()
    s.cborPackTag(CborTag 1'u64)
    pack(s, 42)
    s.setPosition(0)
    let j = toJsonNode(s)
    check j.kind == JObject
    check j["type"].getStr() == "tag"
    check j["tag"].getInt() == 1
    check j["value"].kind == JInt and j["value"].getInt() == 42
    let enc = fromJsonNode(j)
    check enc == "\xc1\x18\x2a"

  test "arrays and maps":
    # array
    var s = CborStream.init()
    let arr = @[1, 2, 3]
    pack(s, arr)
    s.setPosition(0)
    let ja = toJsonNode(s)
    check ja.kind == JArray and ja.len == 3
    let enca = fromJsonNode(ja)
    check fromCbor(enca, seq[int]) == arr

    # map
    var m = initTable[string, int]()
    m["a"] = 1
    s = CborStream.init()
    pack(s, m)
    s.setPosition(0)
    let jm = toJsonNode(s)
    check jm.kind == JObject and jm["a"].getInt() == 1
    let encm = fromJsonNode(jm)
    var md = fromCbor(encm, Table[string, int])
    check md == m

  test "simple values (0..19 except 20..23 handled elsewhere)":
    # 16 -> 0xf0
    var s = CborStream.init("\xf0")
    let j = toJsonNode(s)
    check j.kind == JObject and j["type"].getStr() == "simple"
    check j["value"].getInt() == 16
    let enc = fromJsonNode(j)
    check enc == "\xf0"

  test "floats roundtrip including NaN":
    # A couple of typical values
    for v in [1.5, -2.5, 0.0, 42.125]:
      var s = CborStream.init()
      pack(s, v)
      s.setPosition(0)
      let j = toJsonNode(s)
      check j.kind == JFloat
      let enc = fromJsonNode(j)
      let d = fromCbor(enc, float64)
      check d == v
    # NaN: cannot compare equality, just isNaN
    block:
      var s = CborStream.init()
      var v = NaN
      pack(s, v)
      s.setPosition(0)
      let j = toJsonNode(s)
      check j.kind == JFloat and isNaN(j.getFloat())
      let enc = fromJsonNode(j)
      let d = fromCbor(enc, float64)
      check isNaN(d)
