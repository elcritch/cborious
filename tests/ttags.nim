import unittest
import std/times
import std/strutils
import cborious
import cborious/tags

template checkPackToString(v: CborStream, expected: string) =
  echo "checking " & $v.data.repr() & " (" & $typeof(v.data) & ")" & " to " & expected.repr()
  check v.data.repr() == expected.repr()

suite "CBOR tags & timestamps":
  test "tag 0: RFC3339 string roundtrip & generic skip":
    var dt = initDateTime(21, mMar, 2013, 20, 4, 0, zone = utc())
    var s = CborStream.init()
    s.pack_tagged(dt)
    # C0 (tag 0), then length-prefixed string
    checkPackToString(s, "\xC0\x742013-03-21T20:04:00Z")
    # checkPackToString(s.data, "\xC0\x742013-03-21T20:04:00Z")
    # Unpack as string should ignore tag
    s.setPosition(0)
    let txt = unpack(s, string)
    check txt == "2013-03-21T20:04:00Z"

  test "tag 1: epoch seconds example":
    var t = fromUnix(1363896240'i64)
    var s = CborStream.init()
    s.pack_tagged(t)
    # C1 = tag 1, then 1A = uint32, followed by 0x514B67B0
    check s.data == "\xC1\x1A\x51\x4B\x67\xB0"
    s.setPosition(0)
    # Unpack as integer should ignore tag
    let secs = unpack(s, int64)
    check secs == 1363896240'i64

  test "tag 0: decode into DateTime using format":
    var s = CborStream.init()
    s.pack_tagged(0.CborTag, "2013-03-21T20:04:00Z")
    echo "Packed date: ", s.data.repr()
    s.setPosition(0)

    var dt: DateTime
    unpack_tagged(s, dt)
    check dt == initDateTime(21, mMar, 2013, 20, 4, 0, zone = utc())
