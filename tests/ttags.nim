import unittest
import std/times
import std/strutils
import cborious
import cborious/objects
import cborious/stdtags

template checkPackToString(v: CborStream, expected: string) =
  echo "checking " & $v.data.repr() & " (" & $typeof(v.data) & ")" & " to " & expected.repr()
  check v.data.repr() == expected.repr()

suite "CBOR tags & timestamps":
  test "test cborPackTag":
    var cc = CborStream.init()
    cc.cborPackTag(cborTag(DateTime))
    cc.cborPack("2013-03-21T20:04:00Z")
    checkPackToString(cc, "\192\x742013-03-21T20:04:00Z")

  test "tag 0: string roundtrip & generic skip":
    var s = CborStream.init()
    let dt = parse("2013-03-21T20:04:00Z", "yyyy-MM-dd'T'HH:mm:ss'Z'")
    s.cborPack(dt)
    # C0 (tag 0), then length-prefixed string
    checkPackToString(s, "\xC0\x742013-03-21T20:04:00Z")
    # Unpack as string should ignore tag
    s.setPosition(0)
    let txt = unpack(s, DateTime)
    check txt == dt
