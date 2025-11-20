import std/math
import std/endians

import ../types
import ../stream
import ../cbor
import ../objects

## RFC 8746 helpers for typed arrays and multi-dimensional arrays.
##
## This module implements helpers for the array- and typed-array-related
## tags described by RFC 8746.  It currently provides:
##
## - Plain-array and typed-array wrappers for tag 40 and tag 1040
##   (Section 3.1, multi-dimensional arrays), using either classical
##   CBOR arrays-of-values or RFC 8746 typed arrays as element storage.
## - Homogeneous-array helpers for tag 41 (Section 3.2).
## - Parsing of the typed-number tag range 64..87 (Section 2.1,
##   "Types of Numbers"), exposing the class of number, endianness, and
##   element size.

const
  ## RFC 8746 multi-dimensional array tag (row-major order)
  CborTagArray* = CborTag(40'u64)
  ## RFC 8746 multi-dimensional array tag (column-major order)
  CborTagNdArray* = CborTag(1040'u64)

  ## RFC 8746 homogeneous array tag (Section 3.2).
  CborTagHomArray* = CborTag(41'u64)

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

  TypedNumberEndian* = system.Endianness

  TypedNumberInfo* = object
    ## Parsed information about a typed-number tag in the 64..87 range.
    kind*: TypedNumberKind      ## unsigned int, signed int, or float
    endian*: TypedNumberEndian  ## big or little endian
    bits*: int                  ## number of bits per element (8,16,32,64,128)
    elementBytes*: int          ## number of bytes per element (1,2,4,8,16)
    clamped*: bool              ## true only for uint8-clamped (tag 68)

template assertShapeMatches(lenData: int, shape: openArray[int]) =
  ## Validate that the product of the dimensions in `shape` matches the
  ## number of data elements `lenData`.
  ##
  ## All dimensions MUST be positive (non-zero).  A best-effort overflow
  ## guard avoids raising on multiplication overflow by treating an
  ## overflow as "unknown" and skipping the exact check.
  var prod = 1
  for d in shape:
    if d <= 0:
      raise newException(CborInvalidArgError,
        "dimensions must be positive in shape")
    # avoid overflow exceptions; only check when within bounds
    if prod > 0 and prod <= (high(int) div d):
      prod = prod * d
    else:
      # fall back to best-effort: stop exact multiplication
      prod = lenData
      break
  if prod != lenData:
    raise newException(CborInvalidArgError, "shape does not match data length")


# Homogeneous array helpers (Section 3.2) ---------------------------------

proc cborPackHomogeneousArray*[T](s: Stream, vals: openArray[T]) =
  ## Encode a homogeneous array using RFC 8746 tag 41.
  ##
  ## This simply wraps a classical CBOR array (major type 4) in tag 41,
  ## asserting at the API level that all elements are of the same Nim
  ## type `T`.
  s.cborPackTag(CborTagHomArray)
  s.cborPack(vals)

proc cborUnpackHomogeneousArray*[T](s: Stream, vals: var seq[T]) =
  ## Decode a homogeneous array that was encoded with
  ## `cborPackHomogeneousArray` (RFC 8746 tag 41).
  ##
  ## On success, `vals` receives the elements of the tagged classical
  ## CBOR array as a Nim sequence of `T`.
  s.cborExpectTag(CborTagHomArray)
  s.cborUnpack(vals)

proc cborUnpackHomogeneousArray*[T; N: static[int]](
    s: Stream, vals: var array[N, T]
) =
  ## Decode a homogeneous array into a fixed-size Nim `array[N, T]`.
  ##
  ## The encoded homogeneous array MUST have exactly N elements;
  ## otherwise, a `CborInvalidHeaderError` is raised.
  var tmp: seq[T]
  s.cborUnpackHomogeneousArray(tmp)
  if tmp.len != N:
    raise newException(CborInvalidHeaderError,
      "homogeneous array length mismatch; expected " & $N &
      " elements but got " & $tmp.len)
  var i = 0
  while i < N:
    vals[i] = tmp[i]
    inc i


# Multi-dimensional array helpers (Section 3.1.1, row-major) --------------

proc cborPackNdArrayRowMajor*[T](
    s: Stream, shape: openArray[int], data: openArray[T]
) =
  ## Encode a multi-dimensional array using RFC 8746 tag 40 (row-major
  ## order), with the elements stored as a classical CBOR array
  ## (major type 4) of values.
  ##
  ## `shape` gives the list of dimensions; `data` contains the flattened
  ## elements in row-major order (last dimension contiguous).

  if shape.len == 0:
    raise newException(CborInvalidArgError,
      "multi-dimensional array shape must contain at least one dimension")

  assertShapeMatches(data.len, shape)

  # Tag 40: multi-dimensional array, row-major order
  s.cborPackTag(CborTagArray)

  # Outer array(2): [ dimensions, elements ]
  cborPackInt(s, 2'u64, CborMajor.Array)

  # First element: dimensions as an array of unsigned integers
  cborPackInt(s, uint64(shape.len), CborMajor.Array)
  for d in shape:
    cborPackInt(s, uint64(d), CborMajor.Unsigned)

  # Second element: classical CBOR array of values in row-major order
  s.cborPack(data)

proc cborPackNdArrayRowMajorTyped*[T: SomeInteger | SomeFloat](
    s: Stream, shape: openArray[int], data: openArray[T],
    endian = system.cpuEndian
) =
  ## Encode a multi-dimensional array using RFC 8746 tag 40 (row-major
  ## order), with the elements stored as a typed array (Section 2).
  ##
  ## This matches the structure shown in RFC 8746 Figure 1: the second
  ## element of the outer array is itself a typed array tagged with one
  ## of the tags 64..87.

  if shape.len == 0:
    raise newException(CborInvalidArgError,
      "multi-dimensional array shape must contain at least one dimension")

  assertShapeMatches(data.len, shape)

  # Tag 40: multi-dimensional array, row-major order
  s.cborPackTag(CborTagArray)

  # Outer array(2): [ dimensions, elements ]
  cborPackInt(s, 2'u64, CborMajor.Array)

  # First element: dimensions as an array of unsigned integers
  cborPackInt(s, uint64(shape.len), CborMajor.Array)
  for d in shape:
    cborPackInt(s, uint64(d), CborMajor.Unsigned)

  # Second element: RFC 8746 typed array of numeric values in row-major order
  s.cborPackTypedArray(data, endian)

proc cborUnpackNdArrayRowMajor*[T](
    s: Stream, shapeOut: var seq[int], dataOut: var seq[T]
) =
  ## Decode a multi-dimensional array that was encoded with
  ## `cborPackNdArrayRowMajor` (RFC 8746 tag 40, row-major order).
  ##
  ## On success, `shapeOut` receives the list of dimensions and
  ## `dataOut` the flattened elements in row-major order.

  # Expect tag 40; allow a leading self-described CBOR tag.
  s.cborExpectTag(CborTagArray)

  # Outer array(2): [ dimensions, elements ]
  let (majOuter, aiOuter) = s.readInitial()
  if majOuter != CborMajor.Array:
    raise newException(CborInvalidHeaderError,
      "expected outer array for multi-dimensional array")

  if aiOuter == AiIndef:
    raise newException(CborInvalidHeaderError,
      "indefinite-length outer array not supported for multi-dimensional array")

  let outerLen = int(s.readAddInfo(aiOuter))
  if outerLen != 2:
    raise newException(CborInvalidHeaderError,
      "multi-dimensional array outer array must contain exactly two elements")

  # First element: dimensions array
  let (majDims, aiDims) = s.readInitial()
  if majDims != CborMajor.Array:
    raise newException(CborInvalidHeaderError,
      "expected dimensions array for multi-dimensional array")

  if aiDims == AiIndef:
    raise newException(CborInvalidHeaderError,
      "indefinite-length dimensions array not supported for multi-dimensional array")

  let dimsLen = int(s.readAddInfo(aiDims))
  if dimsLen <= 0:
    raise newException(CborInvalidHeaderError,
      "multi-dimensional array must have at least one dimension")

  shapeOut.setLen(dimsLen)
  for i in 0 ..< dimsLen:
    var dimVal: uint64
    s.cborUnpack(dimVal)
    if dimVal == 0'u64:
      raise newException(CborInvalidHeaderError,
        "dimensions must be non-zero in multi-dimensional array")
    if dimVal > uint64(high(int)):
      raise newException(CborOverflowError,
        "dimension value too large for host int")
    shapeOut[i] = int(dimVal)

  # Second element: either a classical CBOR array of values, or a typed
  # array (tags 64..87) as in RFC 8746 Figure 1, or (optionally) a
  # homogeneous array (tag 41) of values.

  let posVals = s.getPosition()
  let (majVals, aiVals) = s.readInitial()

  if majVals == CborMajor.Array:
    if aiVals == AiIndef:
      raise newException(CborInvalidHeaderError,
        "indefinite-length element arrays are not supported for multi-dimensional array")

    let nVals = int(s.readAddInfo(aiVals))
    if nVals < 0:
      raise newException(CborInvalidHeaderError,
        "negative length for multi-dimensional array elements")

    dataOut.setLen(nVals)
    for i in 0 ..< nVals:
      s.cborUnpack(dataOut[i])

  elif majVals == CborMajor.Tag:
    let tagVal = s.readAddInfo(aiVals)
    s.setPosition(posVals)

    if tagVal >= 64'u64 and tagVal <= 87'u64:
      # RFC 8746 typed array (Section 2) used as the second element,
      # as in Figure 1.  Decode directly into the numeric sequence.
      when T is SomeInteger or T is SomeFloat:
        let info = parseTypedNumberTag(CborTag(tagVal))
        # Decode the typed array into `dataOut`, keeping the in-memory
        # representation in the element endianness defined by the tag.
        s.cborUnpackTypedArray(dataOut, info.endian)

        # If the tagged element endianness differs from the host
        # endianness, normalize elements to host order so that
        # `dataOut` holds usable numeric values.
        if info.elementBytes > 1 and info.elementBytes <= 8 and
           info.endian != system.cpuEndian:
          when sizeof(T) == 2:
            for item in dataOut.mitems():
              swapEndian16(addr(item), addr(item))
          elif sizeof(T) == 4:
            for item in dataOut.mitems():
              swapEndian32(addr(item), addr(item))
          elif sizeof(T) == 8:
            for item in dataOut.mitems():
              swapEndian64(addr(item), addr(item))
          else:
            discard
      else:
        raise newException(CborInvalidHeaderError,
          "multi-dimensional typed array elements require a numeric target type")

    else:
      raise newException(CborInvalidHeaderError,
        "unsupported tag for multi-dimensional array elements")

  else:
    raise newException(CborInvalidHeaderError,
      "multi-dimensional array elements must be an array or typed array")

  assertShapeMatches(dataOut.len, shapeOut)


# Multi-dimensional array helpers (Section 3.1.2, column-major) ----------

proc cborPackNdArrayColumnMajor*[T](
    s: Stream, shape: openArray[int], data: openArray[T]
) =
  ## Encode a multi-dimensional array using RFC 8746 tag 1040
  ## (column-major order), with the elements stored as a classical CBOR
  ## array (major type 4) of values.
  ##
  ## `shape` gives the list of dimensions; `data` contains the flattened
  ## elements in column-major order (first dimension contiguous).

  if shape.len == 0:
    raise newException(CborInvalidArgError,
      "multi-dimensional array shape must contain at least one dimension")

  assertShapeMatches(data.len, shape)

  # Tag 1040: multi-dimensional array, column-major order
  s.cborPackTag(CborTagNdArray)

  # Outer array(2): [ dimensions, elements ]
  cborPackInt(s, 2'u64, CborMajor.Array)

  # First element: dimensions as an array of unsigned integers
  cborPackInt(s, uint64(shape.len), CborMajor.Array)
  for d in shape:
    cborPackInt(s, uint64(d), CborMajor.Unsigned)

  # Second element: classical CBOR array of values in column-major order
  s.cborPack(data)

proc cborPackNdArrayColumnMajorTyped*[T: SomeInteger | SomeFloat](
    s: Stream, shape: openArray[int], data: openArray[T],
    endian = system.cpuEndian
) =
  ## Encode a multi-dimensional array using RFC 8746 tag 1040
  ## (column-major order), with the elements stored as a typed array
  ## (Section 2).  The second element of the outer array is a typed
  ## array tagged with one of the tags 64..87.

  if shape.len == 0:
    raise newException(CborInvalidArgError,
      "multi-dimensional array shape must contain at least one dimension")

  assertShapeMatches(data.len, shape)

  # Tag 1040: multi-dimensional array, column-major order
  s.cborPackTag(CborTagNdArray)

  # Outer array(2): [ dimensions, elements ]
  cborPackInt(s, 2'u64, CborMajor.Array)

  # First element: dimensions as an array of unsigned integers
  cborPackInt(s, uint64(shape.len), CborMajor.Array)
  for d in shape:
    cborPackInt(s, uint64(d), CborMajor.Unsigned)

  # Second element: RFC 8746 typed array of numeric values in column-major order
  s.cborPackTypedArray(data, endian)

proc cborUnpackNdArrayColumnMajor*[T](
    s: Stream, shapeOut: var seq[int], dataOut: var seq[T]
) =
  ## Decode a multi-dimensional array that was encoded with
  ## `cborPackNdArrayColumnMajor` or `cborPackNdArrayColumnMajorTyped`
  ## (RFC 8746 tag 1040, column-major order).
  ##
  ## On success, `shapeOut` receives the list of dimensions and
  ## `dataOut` the flattened elements in column-major order.

  # Expect tag 1040; allow a leading self-described CBOR tag.
  s.cborExpectTag(CborTagNdArray)

  # Outer array(2): [ dimensions, elements ]
  let (majOuter, aiOuter) = s.readInitial()
  if majOuter != CborMajor.Array:
    raise newException(CborInvalidHeaderError,
      "expected outer array for multi-dimensional array")

  if aiOuter == AiIndef:
    raise newException(CborInvalidHeaderError,
      "indefinite-length outer array not supported for multi-dimensional array")

  let outerLen = int(s.readAddInfo(aiOuter))
  if outerLen != 2:
    raise newException(CborInvalidHeaderError,
      "multi-dimensional array outer array must contain exactly two elements")

  # First element: dimensions array
  let (majDims, aiDims) = s.readInitial()
  if majDims != CborMajor.Array:
    raise newException(CborInvalidHeaderError,
      "expected dimensions array for multi-dimensional array")

  if aiDims == AiIndef:
    raise newException(CborInvalidHeaderError,
      "indefinite-length dimensions array not supported for multi-dimensional array")

  let dimsLen = int(s.readAddInfo(aiDims))
  if dimsLen <= 0:
    raise newException(CborInvalidHeaderError,
      "multi-dimensional array must have at least one dimension")

  shapeOut.setLen(dimsLen)
  for i in 0 ..< dimsLen:
    var dimVal: uint64
    s.cborUnpack(dimVal)
    if dimVal == 0'u64:
      raise newException(CborInvalidHeaderError,
        "dimensions must be non-zero in multi-dimensional array")
    if dimVal > uint64(high(int)):
      raise newException(CborOverflowError,
        "dimension value too large for host int")
    shapeOut[i] = int(dimVal)

  # Second element: either a classical CBOR array of values, or a typed
  # array (tags 64..87) as allowed by RFC 8746.

  let posVals = s.getPosition()
  let (majVals, aiVals) = s.readInitial()

  if majVals == CborMajor.Array:
    if aiVals == AiIndef:
      raise newException(CborInvalidHeaderError,
        "indefinite-length element arrays are not supported for multi-dimensional array")

    let nVals = int(s.readAddInfo(aiVals))
    if nVals < 0:
      raise newException(CborInvalidHeaderError,
        "negative length for multi-dimensional array elements")

    dataOut.setLen(nVals)
    for i in 0 ..< nVals:
      s.cborUnpack(dataOut[i])

  elif majVals == CborMajor.Tag:
    let tagVal = s.readAddInfo(aiVals)
    s.setPosition(posVals)

    if tagVal >= 64'u64 and tagVal <= 87'u64:
      # RFC 8746 typed array used as the second element.  Decode directly
      # into the numeric sequence.
      when T is SomeInteger or T is SomeFloat:
        let info = parseTypedNumberTag(CborTag(tagVal))
        s.cborUnpackTypedArray(dataOut, info.endian)

        if info.elementBytes > 1 and info.elementBytes <= 8 and
           info.endian != system.cpuEndian:
          when sizeof(T) == 2:
            for item in dataOut.mitems():
              swapEndian16(addr(item), addr(item))
          elif sizeof(T) == 4:
            for item in dataOut.mitems():
              swapEndian32(addr(item), addr(item))
          elif sizeof(T) == 8:
            for item in dataOut.mitems():
              swapEndian64(addr(item), addr(item))
          else:
            discard
      else:
        raise newException(CborInvalidHeaderError,
          "multi-dimensional typed array elements require a numeric target type")

    else:
      raise newException(CborInvalidHeaderError,
        "unsupported tag for multi-dimensional array elements")

  else:
    raise newException(CborInvalidHeaderError,
      "multi-dimensional array elements must be an array or typed array")

  assertShapeMatches(dataOut.len, shapeOut)

proc typedNumberTagFor*[T: SomeInteger | SomeFloat](
    endian: TypedNumberEndian; clamped = false
): CborTag =
  ## Select the RFC 8746 typed-number tag in the 64..87 range corresponding
  ## to the Nim numeric type `T`, the desired endianness, and (for uint8)
  ## whether clamped arithmetic is requested.
  ##
  ## The result is suitable for use with `cborPackTypedArray` and
  ## `cborPackTypedArrayConvert`.  Passing the returned tag to
  ## `parseTypedNumberTag` yields a `TypedNumberInfo` whose `kind`,
  ## `bits`, `endian`, and `clamped` fields match the requested
  ## combination, except that 8-bit integers have no little-endian
  ## variants (tag 76 is reserved and MUST NOT be used).

  when T is SomeFloat:
    const bytes = sizeof(T)
    when bytes != 4 and bytes != 8:
      {.error: "typed-number tags currently support only 32-bit and 64-bit float element types".}

    if clamped:
      raise newException(CborInvalidArgError,
        "typed-number tags support clamped semantics only for uint8 arrays")

    when bytes == 4:
      if endian == bigEndian:
        result = CborTagTaFloat32Be
      else:
        result = CborTagTaFloat32Le
    elif bytes == 8:
      if endian == bigEndian:
        result = CborTagTaFloat64Be
      else:
        result = CborTagTaFloat64Le

  elif T is SomeUnsignedInt:
    const bytes = sizeof(T)

    when bytes == 1:
      if clamped:
        result = CborTagTaUint8Clamped
      else:
        if endian != bigEndian:
          raise newException(CborInvalidArgError,
            "tag 68 (uint8 clamped) is reserved; plain uint8 typed arrays use big-endian tag 64")
        result = CborTagTaUint8

    elif bytes == 2:
      if clamped:
        raise newException(CborInvalidArgError,
          "typed-number tags support clamped semantics only for uint8 arrays")
      if endian == bigEndian:
        result = CborTagTaUint16Be
      else:
        result = CborTagTaUint16Le

    elif bytes == 4:
      if clamped:
        raise newException(CborInvalidArgError,
          "typed-number tags support clamped semantics only for uint8 arrays")
      if endian == bigEndian:
        result = CborTagTaUint32Be
      else:
        result = CborTagTaUint32Le

    elif bytes == 8:
      if clamped:
        raise newException(CborInvalidArgError,
          "typed-number tags support clamped semantics only for uint8 arrays")
      if endian == bigEndian:
        result = CborTagTaUint64Be
      else:
        result = CborTagTaUint64Le

    else:
      {.error: "typed-number tags currently support only 8,16,32,64-bit unsigned integer element types".}

  elif T is SomeSignedInt:
    const bytes = sizeof(T)

    when bytes == 1:
      if clamped:
        raise newException(CborInvalidArgError,
          "typed-number tags support clamped semantics only for uint8 arrays")
      if endian != bigEndian:
        raise newException(CborInvalidArgError,
          "tag 76 (little-endian sint8) is reserved and MUST NOT be used")
      result = CborTagTaSint8

    elif bytes == 2:
      if clamped:
        raise newException(CborInvalidArgError,
          "typed-number tags support clamped semantics only for uint8 arrays")
      if endian == bigEndian:
        result = CborTagTaSint16Be
      else:
        result = CborTagTaSint16Le

    elif bytes == 4:
      if clamped:
        raise newException(CborInvalidArgError,
          "typed-number tags support clamped semantics only for uint8 arrays")
      if endian == bigEndian:
        result = CborTagTaSint32Be
      else:
        result = CborTagTaSint32Le

    elif bytes == 8:
      if clamped:
        raise newException(CborInvalidArgError,
          "typed-number tags support clamped semantics only for uint8 arrays")
      if endian == bigEndian:
        result = CborTagTaSint64Be
      else:
        result = CborTagTaSint64Le

    else:
      {.error: "typed-number tags currently support only 8,16,32,64-bit signed integer element types".}

  else:
    {.error: "typedNumberTagFor: typed arrays currently support only integer and float element types".}

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

  result.endian = (if eBit == 0'u8: bigEndian else: littleEndian)

  # Per RFC 8746: bytesPerElement = 2**(f + ll).
  let shiftVal = int(f) + int(ll)
  result.elementBytes = 1 shl shiftVal
  result.bits = result.elementBytes * 8

  # Only tag 68 denotes uint8 clamped arithmetic.
  result.clamped = (v == 68'u64)


# Typed-array helpers (Section 2 "Typed Arrays") ---------------------------

proc cborPackTypedArray*[T: SomeInteger | SomeFloat](s: Stream, data: openArray[T], endian = system.cpuEndian) =
  ## Encode an RFC 8746 typed array (Section 2) for a homogeneous array of
  ## numbers, using the supplied tag in the 64..87 range.
  ##
  ## The tag selects the number class (uint/sint/float), endianness, and
  ## element width; this procedure validates that these agree with the
  ## Nim element type T before encoding.

  let tag: CborTag =
    if sizeof(T) == 1:
      typedNumberTagFor[T](bigEndian)
    else:
      typedNumberTagFor[T](endian)
  let info = parseTypedNumberTag(tag)
  s.cborPackTag(tag)

  if info.elementBytes <= 0 or info.elementBytes > 8:
    raise newException(CborInvalidArgError,
      "unsupported element byte width for typed-array element: " & $info.elementBytes)

  if data.len == 0:
    # Empty typed array: still a valid byte string with length 0.
    cborPackInt(s, 0'u64, CborMajor.Binary)
    return

  let totalBytes = data.len * info.elementBytes
  cborPackInt(s, uint64(totalBytes), CborMajor.Binary)

  when sizeof(T) == 1:
    s.writeData(addr(data[0]), totalBytes)
  elif sizeof(T) in [2,4,8]:
    if info.endian == system.cpuEndian:
      s.writeData(addr(data[0]), totalBytes)
    else:
      for x in data:
        if info.endian == bigEndian:
          static:
            echo "PACK SIZE: ", sizeof(T)
          s.storeBE(x)
        else:
          s.storeLE(x)
  else:
    {.error:
      "unsupported element byte width for typed-array element: " & $elemBytes.}

import std/typetraits

proc cborUnpackTypedArray*[X](
    s: Stream, arrOut: var X, endian = system.cpuEndian
) =
  ## Decode an RFC 8746 typed array that was encoded with cborPackTypedArray.
  ##
  ## The caller supplies the expected tag, and the element type T must be
  ## compatible with the number class and width implied by the tag.
  var tag: CborTag
  if not s.readOneTag(tag):
    raise newException(CborInvalidHeaderError, "expected tag")

  template T(): auto = typetraits.elementType(arrOut)

  let info = parseTypedNumberTag(tag)
  let (major, ai) = s.readInitialSkippingTags()

  if major == CborMajor.Simple and (ai == 22'u8 or ai == 23'u8):
    # Treat null/undefined as empty typed array.
    when arrOut is seq:
      arrOut.setLen(0)
    return

  if major != CborMajor.Binary:
    raise newException(CborInvalidHeaderError, "expected binary string")

  if info.elementBytes <= 0:
    raise newException(CborInvalidHeaderError,
      "invalid element width in typed-array tag")

  # Definite-length byte string
  let totalBytes = int(s.readAddInfo(ai))
  if totalBytes < 0:
    raise newException(CborInvalidHeaderError, "negative length")
  if totalBytes == 0:
    return

  if totalBytes mod info.elementBytes != 0:
    # Consume payload to leave stream at end of the byte string.
    var skipped = 0
    while skipped < totalBytes:
      discard s.readChar()
      inc skipped
    raise newException(CborInvalidHeaderError,
      "typed-array byte string length not a multiple of element size")

  if info.elementBytes > 8:
    var skipped = 0
    while skipped < totalBytes:
      discard s.readChar()
      inc skipped
    raise newException(CborInvalidHeaderError,
      "unsupported element byte width for typed-array decode: " & $info.elementBytes)

  let count = totalBytes div info.elementBytes
  when arrOut is seq:
    arrOut.setLen(count)
  let availBytes = min(totalBytes, arrOut.len() * info.elementBytes)

  if sizeof(T) != info.elementBytes:
      raise newException(CborInvalidHeaderError,
                          "typed-array element size mismatch; " &
                          "got elem size: " & $info.elementBytes &
                          " for type: " & $(T))

  when sizeof(T) == 1:
    let ln = s.readData(arrOut[0].addr, availBytes)
    assert ln == availBytes
  elif sizeof(T) in [2,4,8]:
    if info.endian == endian:
      let ln = s.readData(arrOut[0].addr, availBytes)
      assert ln == availBytes
    else:
      for idx in 0 ..< count:
        arrOut[idx] =
          if info.endian == bigEndian:
            s.unstoreBE(typeof(T))
          else:
            s.unstoreLE(typeof(T))
  else:
    {.error:
      "unsupported element byte width for typed-array element".}
