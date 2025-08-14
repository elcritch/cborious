import unittest
import cborious
import std/streams

suite "CborStream encode/decode":
  test "int and bool via CborStream":
    let s = CborStream.init()
    stream.encode(s, 42)
    stream.encode(s, true)
    # Now decode back from the same stream; reset position first
    s.setPosition(0)
    let i = stream.decodeInt64(s)
    check i == 42'i64
    let b = stream.decodeBool(s)
    check b == true
