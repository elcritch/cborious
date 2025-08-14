import unittest
import cborious
import std/streams

suite "CborStream pack/unpack":
  test "int and bool via CborStream":
    let s = CborStream.init()
    s.pack(42)
    s.pack(true)
    # Now unpack back from the same stream; reset position first
    s.setPosition(0)
    let i = s.unpack(int64)
    check i == 42'i64
    let b = s.unpack(bool)
    check b == true
