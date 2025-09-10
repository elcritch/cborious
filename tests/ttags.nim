import unittest
import std/times
import std/strutils
import cborious
import cborious/stdtags

type Foo = object
    bar: int

proc cborTag(tp: typedesc[Foo]): CborTag =
    result = 3.CborTag

type Person = object
    name: string
    age: int
    active: bool

proc cborTag(tp: typedesc[Person]): CborTag =
    result = 29.CborTag

suite "CBOR tags & timestamps":
  test "test cborPackTag":
    var cc = CborStream.init()
    cc.cborPackTag(cborTag(DateTime))
    cc.cborPack("2013-03-21T20:04:00Z")
    check cc.data.repr() == repr("\192\x742013-03-21T20:04:00Z")

  test "tag 0: string roundtrip & generic skip":
    var s = CborStream.init()
    let dts = "2013-03-21T20:04:00Z"
    var dt: DateTime = parse(dts, "yyyy-MM-dd'T'HH:mm:ss'Z'")
    let x = toCbor(dt)
    s.cborPack(dt)
    # C0 (tag 0), then length-prefixed string
    check s.data.repr() == repr("\xC0" & x)
    # Unpack as string should ignore tag
    s.setPosition(0)
    let txt = unpack(s, DateTime)
    check txt == dt

  test "tag 3: foo roundtrip & generic skip":
    let x = toCbor((bar: 3))
    echo "X: ", x.repr
    var s = CborStream.init()
    var p = Foo(bar: 3)
    s.cborPack(p)
    check s.data.repr() == repr("\xC3" & x)

  test "tag 29: person roundtrip & generic skip":
    var s = CborStream.init()
    var p = Person(name: "Ann", age: 30, active: true)
    s.cborPack(p)
    check s.data.repr() == repr("\216\29" & "\x83\x63Ann\x18\x1e\xf5")
    # s.setPosition(0)
    # let pp = unpack(s, Person)
    # check pp == p
