import std/unittest
import std/strutils
import std/endians
import stew/byteutils

import cborious/stream
import cborious/objects
import cborious/types
import cborious/cbor
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

  test "parse typed-number tags 64..87 (selected cases)":
    # uint8 Typed Array (tag 64)
    var info = parseTypedNumberTag(CborTagTaUint8)
    check info.kind == tnkUint
    check info.bits == 8
    check info.elementBytes == 1
    check info.endian == bigEndian
    check not info.clamped

    # uint8 Typed Array, clamped arithmetic (tag 68)
    info = parseTypedNumberTag(CborTagTaUint8Clamped)
    check info.kind == tnkUint
    check info.bits == 8
    check info.elementBytes == 1
    # Endianness is redundant for 8-bit but still decodes from the tag.
    check info.endian == littleEndian
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
    check info.endian == bigEndian

    info = parseTypedNumberTag(CborTagTaUint16Le)
    check info.kind == tnkUint
    check info.bits == 16
    check info.elementBytes == 2
    check info.endian == littleEndian

    # sint32 big-endian / little-endian (tags 74, 78)
    info = parseTypedNumberTag(CborTagTaSint32Be)
    check info.kind == tnkSint
    check info.bits == 32
    check info.elementBytes == 4
    check info.endian == bigEndian

    info = parseTypedNumberTag(CborTagTaSint32Le)
    check info.kind == tnkSint
    check info.bits == 32
    check info.elementBytes == 4
    check info.endian == littleEndian

    # IEEE 754 binary64, big-endian / little-endian (tags 82, 86)
    info = parseTypedNumberTag(CborTagTaFloat64Be)
    check info.kind == tnkFloat
    check info.bits == 64
    check info.elementBytes == 8
    check info.endian == bigEndian

    info = parseTypedNumberTag(CborTagTaFloat64Le)
    check info.kind == tnkFloat
    check info.bits == 64
    check info.elementBytes == 8
    check info.endian == littleEndian

  test "parseTypedNumberTag rejects reserved/invalid tags":
    # Tag 76 is reserved for little-endian sint8 and MUST NOT be used.
    expect CborInvalidArgError:
      discard parseTypedNumberTag(CborTag(76'u64))

    # Tags outside 64..87 are not typed-number tags.
    expect CborInvalidArgError:
      discard parseTypedNumberTag(CborTag(40'u64))

  test "typedNumberTagFor maps Nim types to typed-number tags":
    # Unsigned integers
    check typedNumberTagFor[uint8](bigEndian) == CborTagTaUint8
    check typedNumberTagFor[uint8](bigEndian, clamped = true) == CborTagTaUint8Clamped

    check typedNumberTagFor[uint16](bigEndian) == CborTagTaUint16Be
    check typedNumberTagFor[uint16](littleEndian) == CborTagTaUint16Le

    check typedNumberTagFor[uint32](bigEndian) == CborTagTaUint32Be
    check typedNumberTagFor[uint32](littleEndian) == CborTagTaUint32Le

    check typedNumberTagFor[uint64](bigEndian) == CborTagTaUint64Be
    check typedNumberTagFor[uint64](littleEndian) == CborTagTaUint64Le

    # Signed integers
    check typedNumberTagFor[int8](bigEndian) == CborTagTaSint8

    check typedNumberTagFor[int16](bigEndian) == CborTagTaSint16Be
    check typedNumberTagFor[int16](littleEndian) == CborTagTaSint16Le

    check typedNumberTagFor[int32](bigEndian) == CborTagTaSint32Be
    check typedNumberTagFor[int32](littleEndian) == CborTagTaSint32Le

    check typedNumberTagFor[int64](bigEndian) == CborTagTaSint64Be
    check typedNumberTagFor[int64](littleEndian) == CborTagTaSint64Le

    # Floats
    check typedNumberTagFor[float64](bigEndian) == CborTagTaFloat64Be
    check typedNumberTagFor[float64](littleEndian) == CborTagTaFloat64Le

    # Round-trip sanity check for a few types
    block:
      let tag = typedNumberTagFor[int32](littleEndian)
      let info = parseTypedNumberTag(tag)
      check info.kind == tnkSint
      check info.bits == sizeof(int32) * 8
      check info.endian == littleEndian

    block:
      let tag = typedNumberTagFor[uint16](bigEndian)
      let info = parseTypedNumberTag(tag)
      check info.kind == tnkUint
      check info.bits == sizeof(uint16) * 8
      check info.endian == bigEndian

    block:
      let tag = typedNumberTagFor[float64](littleEndian)
      let info = parseTypedNumberTag(tag)
      check info.kind == tnkFloat
      check info.bits == sizeof(float64) * 8
      check info.endian == littleEndian

  test "uint8 typed array via tag 64 (ta-uint8)":
    let dataIn = @[uint8(0), uint8(1), uint8(255)]
    var s = CborStream.init()
    s.cborPackTypedArray(dataIn)

    # Check outer tag and that payload is a byte string
    var st = CborStream.init(s.data)
    var tag: CborTag
    check st.readOneTag(tag)
    check tag == CborTagTaUint8

    let (maj, ai) = st.readInitial()
    check maj == CborMajor.Binary

    # Check raw CBOR bytes (D8 40 43 00 01 FF)
    let hex = s.data.toBytes().toHexPretty()
    check hex == "D8 40 43 00 01 FF"

    # Decode back to values
    var st2 = CborStream.init(s.data)
    var outArr: seq[uint8]
    st2.cborUnpackTypedArray(outArr)
    check outArr == dataIn

  test "uint8 typed array via tag 64 (ta-uint8) into an array":
    let dataIn = [uint8(0), uint8(1), uint8(255)]
    var s = CborStream.init()
    s.cborPackTypedArray(dataIn)

    # Check outer tag and that payload is a byte string
    var st = CborStream.init(s.data)
    var tag: CborTag
    check st.readOneTag(tag)
    check tag == CborTagTaUint8

    let (maj, ai) = st.readInitial()
    check maj == CborMajor.Binary

    # Check raw CBOR bytes (D8 40 43 00 01 FF)
    let hex = s.data.toBytes().toHexPretty()
    check hex == "D8 40 43 00 01 FF"

    # Decode back to values
    var st2 = CborStream.init(s.data)
    var outArr: array[2, uint8]
    st2.cborUnpackTypedArray(outArr)
    check outArr == dataIn[0..1]

  #test "uint8 typed array via tag 64 (ta-uint8) via tagged type":
  #  type TypedArray = 

  test "sint16 typed arrays via tags 73/77 (ta-sint16be/le)":
    let dataIn = @[int16(-2), int16(1234), int16(-32768), int16(0), int16(32767)]

    # Big-endian
    var sBe = CborStream.init()
    #sBe.cborPackTypedArray(CborTagTaSint16Be, dataIn)
    sBe.cborPackTypedArray(dataIn, bigEndian)

    var tagBe: CborTag
    var stBe = CborStream.init(sBe.data)
    check stBe.readOneTag(tagBe)
    check tagBe == CborTagTaSint16Be

    let hexBe = sBe.data.toBytes().toHexPretty()
    # Tag 73 (0x49), byte string of 10 bytes (5 * 2)
    # Header: D8 49 (tag 73), 4A (binary string len 10)
    check hexBe.startsWith("D8 49 4A")

    var outBe: seq[int16]
    var stBe2 = CborStream.init(sBe.data)
    #stBe2.cborUnpackTypedArray(CborTagTaSint16Be, outBe)
    stBe2.cborUnpackTypedArray(outBe, bigEndian)
    when system.cpuEndian == littleEndian:
      for item in outBe.mitems():
        swapEndian16(addr(item), addr(item))
    check outBe == dataIn

    # Little-endian
    var sLe = CborStream.init()
    #sLe.cborPackTypedArray(CborTagTaSint16Le, dataIn)
    sLe.cborPackTypedArray(dataIn)

    var tagLe: CborTag
    var stLe = CborStream.init(sLe.data)
    check stLe.readOneTag(tagLe)
    check tagLe == CborTagTaSint16Le

    let hexLe = sLe.data.toBytes().toHexPretty()
    # Tag 77 (0x4D), byte string of 10 bytes (5 * 2)
    # Header: D8 4D (tag 77), 4A (binary string len 10)
    check hexLe.startsWith("D8 4D 4A")

    var outLe: seq[int16]
    var stLe2 = CborStream.init(sLe.data)
    #stLe2.cborUnpackTypedArray(CborTagTaSint16Le, outLe)
    stLe2.cborUnpackTypedArray(outLe, littleEndian)
    when system.cpuEndian == bigEndian:
      for item in outBe.mitems():
        swapEndian16(addr(item), addr(item))
    check outLe == dataIn

  test "float64 typed arrays via tags 82/86 (ta-float64be/le)":
    let dataIn = @[1.0'f64, -2.0'f64, 3.5'f64]

    # Big-endian float64 typed array (tag 82)
    var sBe = CborStream.init()
    sBe.cborPackTypedArray(dataIn, bigEndian)

    var tagBe: CborTag
    var stBe = CborStream.init(sBe.data)
    check stBe.readOneTag(tagBe)
    check tagBe == CborTagTaFloat64Be

    let hexBe = sBe.data.toBytes().toHexPretty()
    # D8 52 58 18 then three big-endian IEEE 754 binary64 values:
    # 1.0  -> 3F F0 00 00 00 00 00 00
    # -2.0 -> C0 00 00 00 00 00 00 00
    # 3.5  -> 40 0C 00 00 00 00 00 00
    check hexBe == "D8 52 58 18 3F F0 00 00 00 00 00 00 C0 00 00 00 00 00 00 00 40 0C 00 00 00 00 00 00"

    var outBe: seq[float64]
    var stBe2 = CborStream.init(sBe.data)
    stBe2.cborUnpackTypedArray(outBe, bigEndian)
    check outBe.len == dataIn.len
    when system.cpuEndian == littleEndian:
      for item in outBe.mitems():
        swapEndian64(addr(item), addr(item))
    check outBe == dataIn

    # Little-endian float64 typed array (tag 86)
    var sLe = CborStream.init()
    sLe.cborPackTypedArray(dataIn)

    var tagLe: CborTag
    var stLe = CborStream.init(sLe.data)
    check stLe.readOneTag(tagLe)
    check tagLe == CborTagTaFloat64Le

    let hexLe = sLe.data.toBytes().toHexPretty()
    # D8 56 58 18 then three little-endian IEEE 754 binary64 values:
    # 1.0  -> 00 00 00 00 00 00 F0 3F
    # -2.0 -> 00 00 00 00 00 00 00 C0
    # 3.5  -> 00 00 00 00 00 00 0C 40
    check hexLe == "D8 56 58 18 00 00 00 00 00 00 F0 3F 00 00 00 00 00 00 00 C0 00 00 00 00 00 00 0C 40"

    var outLe: seq[float64]
    var stLe2 = CborStream.init(sLe.data)
    stLe2.cborUnpackTypedArray(outLe, littleEndian)
    check outLe.len == dataIn.len
    when system.cpuEndian == bigEndian:
      for item in outBe.mitems():
        swapEndian64(addr(item), addr(item))
    check outLe == dataIn
