import unittest
import cborious

suite "CBOR objects/tuples":

  type Person = object
    name: string
    age: int
    active: bool

  test "object as array (canonical bytes + roundtrip)":
    let p = Person(name: "Ann", age: 30, active: true)
    # 83, 63 'A''n''n', 18 1e, f5
    check toCbor(p) == "\x83\x63Ann\x18\x1e\xf5"
    var s = CborStream.init()
    pack(s, p)
    s.setPosition(0)
    let d = unpack(s, Person)
    check d == p

  test "object as map (canonical order)":
    let p = Person(name: "Ann", age: 30, active: true)
    let enc = toCbor(p, {CborObjToMap, CborCanonical})
    # Map of 3 entries: keys sorted by canonical CBOR of text: 'age', 'name', 'active'
    check enc == "\xa3\x63age\x18\x1e\x64name\x63Ann\x66active\xf5"
    let d = fromCbor(enc, Person)
    check d == p

  test "tuple as array + map roundtrip":
    type Pt = tuple[x: int, y: string]
    let t: Pt = (x: 5, y: "hi")
    # array form default
    check toCbor(t) == "\x82\x05\x62hi"
    let d1 = fromCbor(toCbor(t), Pt)
    check d1 == t
    # map form
    let encMap = toCbor(t, {CborObjToMap, CborCanonical})
    # keys: 'x', 'y' -> 'x' < 'y'
    check encMap == "\xa2\x61x\x05\x61y\x62hi"
    let d2 = fromCbor(encMap, Pt)
    check d2 == t

