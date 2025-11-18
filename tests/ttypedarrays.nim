import std/unittest
import std/strutils
import stew/byteutils

import cborious/stream
import cborious/objects
import cborious/types
import cborious/edn

import cborious/exts/typedarrays

proc toHexPretty(bs: openArray[byte]): string =
  let x = bs.toHex().toUpperAscii()
  for i, c in x:
    if i > 0 and (i) mod 2 == 0:
      result.add(' ')
    result.add(c)

proc toDecPretty(bs: openArray[byte]): string =
  for i, c in bs:
    #if i > 0 and (i) mod 2 == 0:
    result.add(' ')
    result.add($(c.int))

suite "RFC 8746 array tags":
  test "1D int32 roundtrip via tag 40":
    let dataIn = @[int32(1), int32(-2), int32(123456), int32(-9999)]
    var s = CborStream.init()
    s.cborPackArray1D(dataIn)

    # Validate outer tag
    var st = CborStream.init(s.data)
    var tag: CborTag
    check st.readOneTag(tag)
    check tag == CborTagArray

    # Decode
    var st2 = CborStream.init(s.data)
    var outArr: seq[int32]
    st2.cborUnpackArray1D(outArr)
    check outArr == dataIn

  test "1D float64 roundtrip via tag 40":
    let dataIn = @[1.25'f64, -0.0'f64, 1234.5'f64]
    var s = CborStream.init()
    s.cborPackArray1D(dataIn)

    var st = CborStream.init(s.data)
    var tag: CborTag
    discard st.readOneTag(tag)
    check tag == CborTagArray

    echo "DATA: ", s.data.repr()
    echo "EDN: ", ednDump(s.data)
    echo "HEX: ", s.data.toBytes().toHexPretty()
    echo "DEC: ", s.data.toBytes().toDecPretty()

    var st2 = CborStream.init(s.data)
    var outArr: seq[float64]
    st2.cborUnpackArray1D(outArr)
    check outArr.len == dataIn.len
    for i in 0 ..< outArr.len:
      check outArr[i] == dataIn[i]

  test "ND float32 roundtrip via tag 1040":
    let shape = @[2, 3]
    let dataIn = @[1.0'f32, 2.0'f32, 3.5'f32, -4.25'f32, 5.0'f32, 6.0'f32]
    var s = CborStream.init()
    s.cborPackNdArray(shape, dataIn)

    var st = CborStream.init(s.data)
    var tag: CborTag
    check st.readOneTag(tag)
    check tag == CborTagNdArray

    var st2 = CborStream.init(s.data)
    var shp: seq[int]
    var outArr: seq[float32]
    st2.cborUnpackNdArray(shp, outArr)
    check shp == shape
    check outArr.len == dataIn.len
    for i in 0 ..< outArr.len:
      check outArr[i] == dataIn[i]
