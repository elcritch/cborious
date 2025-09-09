import unittest
import std/times
import std/strutils
import cborious
import cborious/tags

suite "CBOR tags & timestamps":
  test "tag 0: RFC3339 string roundtrip & generic skip":
    var dt = initDateTime(21, mMar, 2013, 20, 4, 0, zone = utc())
    var s = CborStream.init()
    s.pack_tagged(dt)
    # C0 (tag 0), then length-prefixed string
    check s.data.startsWith("\xc0\x74")
    s.setPosition(0)
    # Unpack as string should ignore tag
    let txt = unpack(s, string)
    check txt == "2013-03-21T20:04:00Z"

  test "tag 1: epoch seconds example":
    var t = fromUnix(1363896240'i64)
    var s = CborStream.init()
    s.pack_tagged(t)
    # C1 = tag 1, then 1A = uint32, followed by 0x514B67B0
    check s.data == "\xc1\x1a\x51\x4b\x67\xb0"
    s.setPosition(0)
    # Unpack as integer should ignore tag
    let secs = unpack(s, int64)
    check secs == 1363896240'i64

  test "tag 0: decode into DateTime using format":
    var s = CborStream.init()
    s.pack_tagged(0.CborTag, "2013-03-21T20:04:00Z")
    s.setPosition(0)

    var dt: DateTime
    unpack_tagged(s, dt)
    check dt == initDateTime(21, mMar, 2013, 20, 4, 0, zone = utc())
