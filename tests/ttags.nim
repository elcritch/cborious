import unittest
import std/times
import std/strutils
import cborious
import cborious/objects

template checkPackToString(v: CborStream, expected: string) =
  echo "checking " & $v.data.repr() & " (" & $typeof(v.data) & ")" & " to " & expected.repr()
  check v.data.repr() == expected.repr()

suite "CBOR tags & timestamps":
  test "tag 0: string roundtrip & generic skip":
    var s = CborStream.init()
    s.cborPack("2013-03-21T20:04:00Z")
    # C0 (tag 0), then length-prefixed string
    checkPackToString(s, "\x642013-03-21T20:04:00Z")
    # Unpack as string should ignore tag
    s.setPosition(0)
    let txt = unpack(s, string)
    check txt == "2013-03-21T20:04:00Z"
