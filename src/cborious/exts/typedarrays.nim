import std/math

import ../types
import ../stream
import ../cbor
import ../objects

## RFC 8746 helpers for typed arrays and multi-dimensional arrays.
##
## This module implements helpers for the array- and typed-array-related
## tags described by RFC 8746.  It currently provides:
##
## - Plain-array wrappers for tags 40 and 1040 (Section 3, multi-dimensional
##   arrays), using classical CBOR arrays-of-values.
## - Parsing of the typed-number tag range 64..87 (Section 2.1, "Types of
##   Numbers"), exposing the class of number, endianness, and element size.

const
  ## RFC 8746 array tag (1-D vector semantics)
  CborTagArray* = CborTag(40'u64)
  ## RFC 8746 multi-dimensional array tag (n-D array semantics)
  CborTagNdArray* = CborTag(1040'u64)

  ## RFC 8746 typed array tags for numeric data (Section 2.1).
  ## These correspond to the CDDL typenames in Figure 6.
  CborTagTaUint8*          = CborTag(64'u64)
  CborTagTaUint16Be*       = CborTag(65'u64)
  CborTagTaUint32Be*       = CborTag(66'u64)
  CborTagTaUint64Be*       = CborTag(67'u64)
  CborTagTaUint8Clamped*   = CborTag(68'u64)
  CborTagTaUint16Le*       = CborTag(69'u64)
  CborTagTaUint32Le*       = CborTag(70'u64)
  CborTagTaUint64Le*       = CborTag(71'u64)
  CborTagTaSint8*          = CborTag(72'u64)
  CborTagTaSint16Be*       = CborTag(73'u64)
  CborTagTaSint32Be*       = CborTag(74'u64)
  CborTagTaSint64Be*       = CborTag(75'u64)
  ## 76 is reserved (little-endian sint8; MUST NOT be used).
  CborTagTaSint16Le*       = CborTag(77'u64)
  CborTagTaSint32Le*       = CborTag(78'u64)
  CborTagTaSint64Le*       = CborTag(79'u64)
  CborTagTaFloat16Be*      = CborTag(80'u64)
  CborTagTaFloat32Be*      = CborTag(81'u64)
  CborTagTaFloat64Be*      = CborTag(82'u64)
  CborTagTaFloat128Be*     = CborTag(83'u64)
  CborTagTaFloat16Le*      = CborTag(84'u64)
  CborTagTaFloat32Le*      = CborTag(85'u64)
  CborTagTaFloat64Le*      = CborTag(86'u64)
  CborTagTaFloat128Le*     = CborTag(87'u64)

type
  TypedNumberKind* = enum
    ## RFC 8746 Section 2.1 number classes.
    tnkUint
    tnkSint
    tnkFloat

  TypedNumberEndian* = enum
    tneBigEndian
    tneLittleEndian

  TypedNumberInfo* = object
    ## Parsed information about a typed-number tag in the 64..87 range.
    kind*: TypedNumberKind      ## unsigned int, signed int, or float
    endian*: TypedNumberEndian  ## big or little endian
    bits*: int                  ## number of bits per element (8,16,32,64,128)
    elementBytes*: int          ## number of bytes per element (1,2,4,8,16)
    clamped*: bool              ## true only for uint8-clamped (tag 68)

template assertShapeMatches(lenData: int, shape: openArray[int]) =
  when not defined(release):
    var prod = 1
    for d in shape:
      if d < 0:
        raise newException(CborInvalidArgError, "negative dimension in shape")
      # avoid overflow exceptions; only check when within bounds
      if prod > 0 and d > 0 and prod <= (high(int) div max(1, d)):
        prod = prod * d
      else:
        # fall back to best-effort: stop exact multiplication
        prod = lenData
        break
  if prod != lenData:
      raise newException(CborInvalidArgError, "shape does not match data length")

proc parseTypedNumberTag*(tag: CborTag): TypedNumberInfo =
  ## Parse an RFC 8746 typed-number tag in the range 64..87 (Section 2.1).
  ##
  ## The tag is interpreted as having the bit layout:
  ##   0b010 f s e ll
  ## where:
  ##   - f = 0 for integers, 1 for IEEE 754 binary floats
  ##   - s = 0 for unsigned or float, 1 for signed integers
  ##   - e = 0 for big endian, 1 for little endian
  ##   - ll in {0,1,2,3} selects the length per Table 1.
  ##
  ## The number of bytes per element is 2**(f + ll); bits is 8 * bytes.
  ##
  ## For uint8/sint8, endianness is redundant; tag 76 (little-endian
  ## sint8) is reserved and rejected.  Tag 68 (little-endian uint8) is
  ## re-purposed for clamped uint8 arrays and is reported via `clamped`.
  let v = tag.uint64
  if v < 64'u64 or v > 87'u64:
    raise newException(CborInvalidArgError,
      "tag is not in typed-number range 64..87: " & $v)

  let b = uint8(v) # safe: v <= 255
  # Check constant high bits 0b010.....
  if (b and 0b1110_0000'u8) != 0b0100_0000'u8:
    raise newException(CborInvalidArgError,
      "invalid typed-number tag pattern for tag " & $v)

  let f = (b shr 4) and 0x01'u8
  let sBit = (b shr 3) and 0x01'u8
  let eBit = (b shr 2) and 0x01'u8
  let ll = b and 0x03'u8

  # Reject the reserved sint8 little-endian tag (value 76).
  if v == 76'u64:
    raise newException(CborInvalidArgError,
      "tag 76 (little-endian sint8) is reserved and MUST NOT be used")

  # Number class: integer vs float; signedness only for integers.
  if f == 0'u8:
    if sBit == 0'u8:
      result.kind = tnkUint
    else:
      result.kind = tnkSint
  else:
    result.kind = tnkFloat

  result.endian = (if eBit == 0'u8: tneBigEndian else: tneLittleEndian)

  # Per RFC 8746: bytesPerElement = 2**(f + ll).
  let shiftVal = int(f) + int(ll)
  result.elementBytes = 1 shl shiftVal
  result.bits = result.elementBytes * 8

  # Only tag 68 denotes uint8 clamped arithmetic.
  result.clamped = (v == 68'u64)

# 1-D array wrappers ---------------------------------------------------------

proc cborPackArray1D*[T](s: Stream, data: openArray[T]) =
  ## Encode a 1-D array using RFC 8746 tag 40, with content as a plain
  ## CBOR array-of-values. This is a valid representation per RFC 8746.
  s.cborPackTag(CborTagArray)
  s.cborPack(data)

proc cborUnpackArray1D*[T](s: Stream, arrOut: var seq[T]) =
  ## Decode a 1-D array previously encoded with cborPackArray1D.
  s.cborExpectTag(CborTagArray)
  s.cborUnpack(arrOut)

# n-D array wrappers ---------------------------------------------------------

proc cborPackNdArray*[T](s: Stream, shape: openArray[int], data: openArray[T]) =
  ## Encode an n-D array using RFC 8746 tag 1040.
  ## Content is the two-element CBOR array: [shape, flatData], where
  ## - shape is a CBOR array of non-negative integers
  ## - flatData is a CBOR array-of-values in row-major order
  assertShapeMatches(data.len, shape)
  s.cborPackTag(CborTagNdArray)
  # two elements follow: shape, data
  cborPackInt(s, 2'u64, CborMajor.Array)
  s.cborPack(shape)
  s.cborPack(data)

proc cborUnpackNdArray*[T](s: Stream, shape: var seq[int], dataOut: var seq[T]) =
  ## Decode an n-D array previously encoded with cborPackNdArray.
  s.cborExpectTag(CborTagNdArray)
  let (m, ai) = s.readInitial()
  if m != CborMajor.Array:
    raise newException(CborInvalidHeaderError, "expected array for ndarray payload")
  var count: int
  if ai == AiIndef:
    count = -1 # accept indefinite but require exactly two items
  else:
    count = int(s.readAddInfo(ai))
  # Expect two items: shape, data
  s.cborUnpack(shape)
  s.cborUnpack(dataOut)
  when not defined(release):
    assertShapeMatches(dataOut.len, shape)
  if count >= 0:
    if count != 2:
      raise newException(CborInvalidHeaderError, "ndarray payload must have two elements [shape, data]")
  else:
    # consume break for indefinite-length array
    let br = s.readChar()
    if uint8(ord(br)) != 0xff'u8:
      raise newException(CborInvalidHeaderError, "missing break in indefinite array")
