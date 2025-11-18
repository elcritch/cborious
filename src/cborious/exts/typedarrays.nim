import std/math

import ../types
import ../stream
import ../cbor
import ../objects

## RFC 8746 helpers for arrays and multi-dimensional arrays.
##
## This module implements tag wrappers for arrays as described by RFC 8746,
## leveraging the fact that tags 40 and 1040 accept multiple ways to represent
## arrays: plain CBOR arrays-of-values as well as packed representations.
##
## We start by providing the plain-array forms which are unambiguous and
## interoperable. The packing into typed byte strings can be added on top
## of these helpers in a future iteration.

const
  ## RFC 8746 array tag (1-D vector semantics)
  CborTagArray* = CborTag(40'u64)
  ## RFC 8746 multi-dimensional array tag (n-D array semantics)
  CborTagNdArray* = CborTag(1040'u64)

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

