import unittest
import std/strutils
import std/tables
import std/times
import cborious
import cborious/edn
import cborious/stdtags

template EDNof[T](v: T): string =
  ednDump(toCbor(v))

suite "EDN pretty printer":
  test "integers and negatives":
    check EDNof(0) == "0"
    check EDNof(1) == "1"
    check EDNof(10) == "10"
    check EDNof(-1) == "-1"
    check EDNof(-10) == "-10"

  test "booleans and null/undefined":
    check EDNof(true) == "true"
    check EDNof(false) == "false"
    block:
      var s = CborStream.init()
      s.cborPackNull()
      check ednDump(s.data) == "null"
    block:
      var s = CborStream.init()
      s.cborPackUndefined()
      check ednDump(s.data) == "undefined"

  test "text string escaping":
    check EDNof("") == "\"\""
    check EDNof("hi") == "\"hi\""
    check EDNof("a\n\t\"") == "\"a\\n\\t\\\"\""

  test "byte strings (hex)":
    let b = @[0x00'u8, 0xff'u8, 0x0a'u8]
    check EDNof(b) == "h'00ff0a'"

  test "arrays and maps":
    check EDNof(@[1,2,3]) == "[1, 2, 3]"
    block:
      var t = initTable[string, int]()
      t["a"] = 1
      check ednDump(toCbor(t)) == "{\"a\": 1}"

  test "floats and specials":
    check EDNof(1.5) == "1.5"
    block:
      var s = CborStream.init()
      pack(s, Inf)
      check ednDump(s.data) == "Infinity"
    block:
      var s = CborStream.init()
      pack(s, NegInf)
      check ednDump(s.data) == "-Infinity"
    block:
      var n = NaN
      var s = CborStream.init()
      pack(s, n)
      check ednDump(s.data) == "NaN"

  test "tags generic form":
    var dt: DateTime = parse("2013-03-21T20:04:00Z", "yyyy-MM-dd'T'HH:mm:ss'Z'")
    var s = CborStream.init()
    pack(s, dt)
    let edn = ednDump(s.data)
    check edn.contains("0(\"") and edn.endsWith(")")

  test "indefinite strings and arrays":
    # Text string: 0x7f, 'a', 'b', break
    let indefTxt = "\x7f\x61a\x61b\xff"
    check ednDump(indefTxt) == "\"ab\""
    # Array: 0x9f, 1, 2, break
    let indefArr = "\x9f\x01\x02\xff"
    check ednDump(indefArr) == "[1, 2]"
