import unittest
import std/times
import std/strutils
import cborious


suite "CBOR tags & timestamps":
  type Person = object
    name: string
    age: int
    active: bool

  proc cborTag(tp: typedesc[Person]): CborTag =
    result = 10.CborTag

  test "test cborPackTag":
    var cc = CborStream.init()
    cc.cborPackTag(cborTag(DateTime))
    cc.cborPack("2013-03-21T20:04:00Z")
    check cc.data.repr() == repr("\192\x742013-03-21T20:04:00Z")

  # test "tag 0: string roundtrip & generic skip":
  #   var s = CborStream.init()
  #   var dt: DateTime = parse("2013-03-21T20:04:00Z", "yyyy-MM-dd'T'HH:mm:ss'Z'")
  #   s.cborPack(dt)
  #   static: echo "CHECK: IS DT OBJECT: ", dt is object
  #   # C0 (tag 0), then length-prefixed string
  #   check s.data.repr() == repr("\xC0\x742013-03-21T20:04:00Z")
  #   # Unpack as string should ignore tag
  #   s.setPosition(0)
  #   let txt = unpack(s, DateTime)
  #   check txt == dt

  test "tag 10: person roundtrip & generic skip":
    var s = CborStream.init()
    var p = Person(name: "Ann", age: 30, active: true)
    s.cborPack(p)
    check s.data.repr() == repr("\192\10" & "\xa3\x63age\x18\x1e\x64name\x63Ann\x66active\xf5")
    # s.setPosition(0)
    # let pp = unpack(s, Person)
    # check pp == p
