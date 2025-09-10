import unittest
import std/strutils
import cborious
import cborious/edn

# suite "EDN":
#   test "parse hex bytes":
#     let edn = "h'0102ff'"
#     let bytes = ednToCbor(edn)
#     # Expect: major 2 (0x40) len=3 -> 0x43 + 01 02 ff
#     check bytes == "\x43\x01\x02\xff"
#     # Back to EDN
#     let txt = cborToEdn(bytes)
#     check txt == "h'0102ff'"

#   test "parse base64 and base64url":
#     # base64 for 0x01 02 03
#     let b64 = ednToCbor("b64'AQID'")
#     check b64 == "\x43\x01\x02\x03"
#     let b64u = ednToCbor("b64u'AQID'")
#     check b64u == b64

#   test "parse base32":
#     # base32 for 0x01 02 03 is AEBAIQ== (RFC4648), decoded to 010203
#     let b32 = ednToCbor("b32'AEBAIQ=='")
#     check b32 == "\x43\x01\x02\x03"

#   test "numbers, bools, null/undefined":
#     check ednToCbor("0") == "\x00"
#     check ednToCbor("-1") == "\x20"
#     check ednToCbor("true") == "\xf5"
#     check ednToCbor("false") == "\xf4"
#     check ednToCbor("null") == "\xf6"
#     check ednToCbor("undefined") == "\xf7"

#   test "floats and specials":
#     # 1.5 canonical packs as half if possible; accept any float encoding back to EDN "1.5"
#     let f = ednToCbor("1.5")
#     let edn = cborToEdn(f)
#     check edn == "1.5"
#     check cborToEdn(ednToCbor("Infinity")) == "Infinity"
#     check cborToEdn(ednToCbor("-Infinity")) == "-Infinity"
#     let n = ednToCbor("NaN")
#     check cborToEdn(n) == "NaN"

#   test "strings":
#     let s = ednToCbor("\"hi\\n\\t\\\"x\"")
#     check cborToEdn(s) == "\"hi\\n\\t\\\"x\""

#   test "arrays and maps":
#     let a = ednToCbor("[1, 2, \"a\"]")
#     check cborToEdn(a) == "[1, 2, \"a\"]"
#     let m = ednToCbor("{\"a\": 1, \"b\": h'ff'}")
#     # Map ordering may vary; re-render should be valid EDN with two pairs
#     let mm = cborToEdn(m)
#     check mm.contains("\"a\": 1")
#     check mm.contains("\"b\": h'ff'")

#   test "tags":
#     let t = ednToCbor("55799(1)")
#     # Tag 55799 + unsigned 1
#     check t == "\xd9\xd9\xf7\x01"
#     check cborToEdn(t) == "55799(1)"

