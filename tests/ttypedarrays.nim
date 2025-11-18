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

suite "RFC 8746 array and typed-number tags":
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

  test "parse typed-number tags 64..87 (selected cases)":
    # uint8 Typed Array (tag 64)
    var info = parseTypedNumberTag(CborTagTaUint8)
    check info.kind == tnkUint
    check info.bits == 8
    check info.elementBytes == 1
    check info.endian == tneBigEndian
    check not info.clamped

    # uint8 Typed Array, clamped arithmetic (tag 68)
    info = parseTypedNumberTag(CborTagTaUint8Clamped)
    check info.kind == tnkUint
    check info.bits == 8
    check info.elementBytes == 1
    # Endianness is redundant for 8-bit but still decodes from the tag.
    check info.endian == tneLittleEndian
    check info.clamped

    # sint8 Typed Array (tag 72)
    info = parseTypedNumberTag(CborTagTaSint8)
    check info.kind == tnkSint
    check info.bits == 8
    check info.elementBytes == 1

    # uint16 big-endian / little-endian (tags 65, 69)
    info = parseTypedNumberTag(CborTagTaUint16Be)
    check info.kind == tnkUint
    check info.bits == 16
    check info.elementBytes == 2
    check info.endian == tneBigEndian

    info = parseTypedNumberTag(CborTagTaUint16Le)
    check info.kind == tnkUint
    check info.bits == 16
    check info.elementBytes == 2
    check info.endian == tneLittleEndian

    # sint32 big-endian / little-endian (tags 74, 78)
    info = parseTypedNumberTag(CborTagTaSint32Be)
    check info.kind == tnkSint
    check info.bits == 32
    check info.elementBytes == 4
    check info.endian == tneBigEndian

    info = parseTypedNumberTag(CborTagTaSint32Le)
    check info.kind == tnkSint
    check info.bits == 32
    check info.elementBytes == 4
    check info.endian == tneLittleEndian

    # IEEE 754 binary64, big-endian / little-endian (tags 82, 86)
    info = parseTypedNumberTag(CborTagTaFloat64Be)
    check info.kind == tnkFloat
    check info.bits == 64
    check info.elementBytes == 8
    check info.endian == tneBigEndian

    info = parseTypedNumberTag(CborTagTaFloat64Le)
    check info.kind == tnkFloat
    check info.bits == 64
    check info.elementBytes == 8
    check info.endian == tneLittleEndian

  test "parseTypedNumberTag rejects reserved/invalid tags":
    # Tag 76 is reserved for little-endian sint8 and MUST NOT be used.
    expect CborInvalidArgError:
      discard parseTypedNumberTag(CborTag(76'u64))

    # Tags outside 64..87 are not typed-number tags.
    expect CborInvalidArgError:
      discard parseTypedNumberTag(CborTag(40'u64))
