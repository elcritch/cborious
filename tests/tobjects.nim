import unittest
import cborious

suite "CBOR objects/tuples":

  type Person = object
    name: string
    age: int
    active: bool

  type Pt = tuple[x: int, y: string]

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

  test "tuple as array roundtrip":
    let t: (int, string) = (5, "hi")
    # array form default
    check toCbor(t) == "\x82\x05\x62hi"
    let d1 = fromCbor(toCbor(t), (int, string))
    check d1 == t

  test "tuple as map roundtrip":
    let t: (int, string) = (5, "hi")
    # map form
    let encMap = toCbor(t, {CborObjToMap, CborCanonical})
    let d2 = fromCbor(encMap, (int, string))
    check d2 == t

  test "named tuple as array roundtrip":
    let t: Pt = (x: 5, y: "hi")
    # array form default
    check toCbor(t) == "\x82\x05\x62hi"
    let d1 = fromCbor(toCbor(t), Pt)
    check d1 == t

  test "named tuple as map roundtrip":
    let t: Pt = (x: 5, y: "hi")
    # map form
    let encMap = toCbor(t, {CborObjToMap, CborCanonical})
    # keys: 'x', 'y' -> 'x' < 'y'
    check encMap == "\xa2\x61x\x05\x61y\x62hi"
    let d2 = fromCbor(encMap, Pt)
    check d2 == t

  test "distinct int field inside object (canonical + roundtrip)":
    type UserId = distinct int64
    type Account = object
      id: UserId
      name: string

    let a = Account(id: UserId(123), name: "bob")
    # Compare against base-type object encoding
    type AccountBase = object
      id: int64
      name: string
    let ab = AccountBase(id: 123, name: "bob")
    check toCbor(a) == toCbor(ab)
    let encMap2 = toCbor(a, {CborObjToMap, CborCanonical})
    check encMap2 == toCbor(ab, {CborObjToMap, CborCanonical})
    # Roundtrip
    let dacc = fromCbor(toCbor(a), Account)
    check int64(a.id) == int64(dacc.id) and a.name == dacc.name

  test "distinct object field inside object (canonical + roundtrip)":
    type P2 = object
      name: string
      age: int
    type DP2 = distinct P2
    type Envelope = object
      who: DP2
      tag: string

    let e = Envelope(who: DP2(P2(name: "Ana", age: 22)), tag: "t")
    type EnvelopeBase = object
      who: P2
      tag: string
    let eb = EnvelopeBase(who: P2(name: "Ana", age: 22), tag: "t")
    # Encodings match base-type encoding (array and map forms)
    check toCbor(e) == toCbor(eb)
    let encMap3 = toCbor(e, {CborObjToMap, CborCanonical})
    check encMap3 == toCbor(eb, {CborObjToMap, CborCanonical})
    # Roundtrip
    let de = fromCbor(toCbor(e), Envelope)
    check P2(de.who).name == P2(e.who).name and P2(de.who).age == P2(e.who).age and de.tag == e.tag

  test "tuple with distinct int (roundtrip + canonical)":
    type OrderId = distinct int
    type T = tuple[id: OrderId, qty: int]
    let tt: T = (id: OrderId(7), qty: 3)
    type TBase = tuple[id: int, qty: int]
    let tb: TBase = (id: 7, qty: 3)
    check toCbor(tt) == toCbor(tb)
    let dtt = fromCbor(toCbor(tt), T)
    check int(dtt.id) == 7 and dtt.qty == 3
