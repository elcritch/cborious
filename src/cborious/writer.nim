import std/bitops
import std/strformat
import types

{.push checks: off.}

proc writeUintArg(dst: var seq[byte], major: CborMajor, n: uint64) =
  ## Encode the CBOR header for an unsigned argument (major 0 or 1),
  ## picking the smallest-length representation.
  if n <= 23'u64:
    dst.add(byte((ord(major) shl 5) or int(n)))
  elif n <= 0xff'u64:
    dst.add(byte((ord(major) shl 5) or 24))
    dst.add(byte(n and 0xff'u64))
  elif n <= 0xffff'u64:
    dst.add(byte((ord(major) shl 5) or 25))
    dst.add(byte((n shr 8) and 0xff'u64))
    dst.add(byte(n and 0xff'u64))
  elif n <= 0xffff_ffff'u64:
    dst.add(byte((ord(major) shl 5) or 26))
    dst.add(byte((n shr 24) and 0xff'u64))
    dst.add(byte((n shr 16) and 0xff'u64))
    dst.add(byte((n shr 8) and 0xff'u64))
    dst.add(byte(n and 0xff'u64))
  else:
    dst.add(byte((ord(major) shl 5) or 27))
    dst.add(byte((n shr 56) and 0xff'u64))
    dst.add(byte((n shr 48) and 0xff'u64))
    dst.add(byte((n shr 40) and 0xff'u64))
    dst.add(byte((n shr 32) and 0xff'u64))
    dst.add(byte((n shr 24) and 0xff'u64))
    dst.add(byte((n shr 16) and 0xff'u64))
    dst.add(byte((n shr 8) and 0xff'u64))
    dst.add(byte(n and 0xff'u64))

proc encodeInt64*(x: int64): seq[byte] =
  ## Encode a Nim int64 into CBOR canonical integer representation.
  result = @[]
  if x >= 0:
    writeUintArg(result, mtUnsigned, uint64(x))
  else:
    let n = uint64(-1'i64 - x)
    writeUintArg(result, mtNegative, n)

proc encodeInt*(x: int): seq[byte] =
  ## Encode machine-sized int via int64 path.
  encodeInt64(x.int64)

proc encodeBool*(b: bool): seq[byte] =
  ## Encode a Nim bool into CBOR simple value true/false.
  result = @[]
  result.add(if b: 0xf5'u8.byte else: 0xf4'u8.byte)
