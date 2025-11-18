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

  TypedNumberEndian* = system.Endianness

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
    for x in data:
      s.write(x)
  elif sizeof(T) in [2,4,8]:
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


proc decodeBitsFromBytes(info: TypedNumberInfo, raw: openArray[byte], offset: int): uint64 =
  ## Decode info.bits bits from raw[offset ..< offset+elementBytes] into a
  ## host-endian unsigned integer value.
  let bytes = info.elementBytes
  if bytes <= 0 or bytes > 8:
    raise newException(CborInvalidHeaderError,
      "unsupported element byte width for typed-array decode: " & $bytes)
  if offset < 0 or offset + bytes > raw.len:
    raise newException(CborInvalidHeaderError,
      "typed-array element extends past end of byte string")
  case bytes
  of 1:
    result = uint64(raw[offset])
  of 2:
    var wire: uint16
    copyMem(addr(wire), addr(raw[offset]), 2)
    var host: uint16
    when system.cpuEndian == littleEndian:
      if info.endian == bigEndian:
        swapEndian16(addr(host), addr(wire))
      else:
        host = wire
    else:
      if info.endian == littleEndian:
        swapEndian16(addr(host), addr(wire))
      else:
        host = wire
    result = uint64(host)
  of 4:
    var wire: uint32
    copyMem(addr(wire), addr(raw[offset]), 4)
    var host: uint32
    when system.cpuEndian == littleEndian:
      if info.endian == bigEndian:
        swapEndian32(addr(host), addr(wire))
      else:
        host = wire
    else:
      if info.endian == littleEndian:
        swapEndian32(addr(host), addr(wire))
      else:
        host = wire
    result = uint64(host)
  of 8:
    var wire: uint64
    copyMem(addr(wire), addr(raw[offset]), 8)
    var host: uint64
    when system.cpuEndian == littleEndian:
      if info.endian == bigEndian:
        swapEndian64(addr(host), addr(wire))
      else:
        host = wire
    else:
      if info.endian == littleEndian:
        swapEndian64(addr(host), addr(wire))
      else:
        host = wire
    result = host
  else:
    raise newException(CborInvalidHeaderError,
      "unsupported element byte width for typed-array decode: " & $bytes)

proc decodeBitsFromStream(info: TypedNumberInfo, s: Stream): uint64 =
  ## Decode info.bits bits for a single typed-array element directly from
  ## the underlying stream, using the generic unstoreBE/unstoreLE helpers
  ## to handle endianness and word size.
  let bytes = info.elementBytes
  if bytes <= 0 or bytes > 8:
    raise newException(CborInvalidHeaderError,
      "unsupported element byte width for typed-array decode: " & $bytes)

  case bytes
  of 1:
    let ch = s.readChar()
    result = uint64(byte(ord(ch)))
  of 2:
    var host: uint16
    if info.endian == bigEndian:
      host = unstoreBE[uint16](s)
    else:
      host = unstoreLE[uint16](s)
    result = uint64(host)
  of 4:
    var host: uint32
    if info.endian == bigEndian:
      host = unstoreBE[uint32](s)
    else:
      host = unstoreLE[uint32](s)
    result = uint64(host)
  of 8:
    var host: uint64
    if info.endian == bigEndian:
      host = unstoreBE[uint64](s)
    else:
      host = unstoreLE[uint64](s)
    result = host
  else:
    raise newException(CborInvalidHeaderError,
      "unsupported element byte width for typed-array decode: " & $bytes)

proc decodeTypedArrayValueFromBits[T](info: TypedNumberInfo, bitsVal: uint64): T =
  ## Convert the unsigned integer bit pattern for a typed-array element back
  ## into a Nim value of type T, ensuring the tag's number class and width
  ## match the requested element type.
  when T is SomeFloat:
    if info.kind != tnkFloat:
      raise newException(CborInvalidHeaderError,
        "typed-array tag does not denote a float class")
    const typeBits = sizeof(T) * 8
    if info.bits != typeBits:
      raise newException(CborInvalidHeaderError,
        "typed-array float width (" & $info.bits &
        " bits) does not match element type (" & $typeBits & " bits)")
    when sizeof(T) == 4:
      let bits32 = uint32(bitsVal and 0xffff_ffff'u64)
      result = T(cast[float32](bits32))
    elif sizeof(T) == 8:
      result = T(cast[float64](bitsVal))
    else:
      {.error: "Unsupported float size for typed arrays".}

  elif T is SomeUnsignedInt:
    if info.kind != tnkUint:
      raise newException(CborInvalidHeaderError,
        "typed-array tag does not denote an unsigned integer class")
    const typeBits = sizeof(T) * 8
    if info.bits != typeBits:
      raise newException(CborInvalidHeaderError,
        "typed-array unsigned width (" & $info.bits &
        " bits) does not match element type (" & $typeBits & " bits)")
    if bitsVal > uint64(high(T)):
      raise newException(CborOverflowError,
        "typed-array unsigned element does not fit target type")
    result = T(bitsVal)

  elif T is SomeSignedInt:
    if info.kind != tnkSint:
      raise newException(CborInvalidHeaderError,
        "typed-array tag does not denote a signed integer class")
    const typeBits = sizeof(T) * 8
    if info.bits != typeBits:
      raise newException(CborInvalidHeaderError,
        "typed-array signed width (" & $info.bits &
        " bits) does not match element type (" & $typeBits & " bits)")

    let bits = info.bits
    var xi: int64
    if bits < 64:
      let signBit = 1'u64 shl (bits - 1)
      if (bitsVal and signBit) != 0'u64:
        let full = 1'u64 shl bits
        xi = int64(bitsVal) - int64(full)
      else:
        xi = int64(bitsVal)
    else:
      xi = cast[int64](bitsVal)

    if xi < int64(low(T)) or xi > int64(high(T)):
      raise newException(CborOverflowError,
        "typed-array signed element does not fit target type")
    result = T(xi)

  else:
    {.error: "Typed arrays currently support only integer and float element types".}

proc cborUnpackTypedArray*[T](s: Stream, tag: static[CborTag], arrOut: var seq[T]) =
  ## Decode an RFC 8746 typed array that was encoded with cborPackTypedArray.
  ##
  ## The caller supplies the expected tag, and the element type T must be
  ## compatible with the number class and width implied by the tag.
  let info = parseTypedNumberTag(tag)
  var tag: CborTag
  if not s.readOneTag(tag):
    raise newException(CborInvalidHeaderError, "expected tag")

  let (major, ai) = s.readInitialSkippingTags()

  if major == CborMajor.Simple and (ai == 22'u8 or ai == 23'u8):
    # Treat null/undefined as empty typed array.
    arrOut.setLen(0)
    return

  if major != CborMajor.Binary:
    raise newException(CborInvalidHeaderError, "expected binary string")

  let elemBytes = info.elementBytes
  if elemBytes <= 0:
    raise newException(CborInvalidHeaderError,
      "invalid element width in typed-array tag")

  # Definite-length byte string
  let totalBytes = int(s.readAddInfo(ai))
  if totalBytes < 0:
    raise newException(CborInvalidHeaderError, "negative length")
  if totalBytes == 0:
    return

  if totalBytes mod elemBytes != 0:
    # Consume payload to leave stream at end of the byte string.
    var skipped = 0
    while skipped < totalBytes:
      discard s.readChar()
      inc skipped
    raise newException(CborInvalidHeaderError,
      "typed-array byte string length not a multiple of element size")

  if elemBytes > 8:
    var skipped = 0
    while skipped < totalBytes:
      discard s.readChar()
      inc skipped
    raise newException(CborInvalidHeaderError,
      "unsupported element byte width for typed-array decode: " & $elemBytes)

  let count = totalBytes div elemBytes
  arrOut.setLen(count)

  
  for idx in 0 ..< count:
    let bitsVal = decodeBitsFromStream(info, s)
    arrOut[idx] = decodeTypedArrayValueFromBits[T](info, bitsVal)
