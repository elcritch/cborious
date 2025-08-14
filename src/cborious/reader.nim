import types

{.push checks: off.}

proc readUintArg(src: openArray[byte], pos: var int, ai: uint8): uint64 =
  ## Read the unsigned argument value according to additional info `ai`.
  if ai <= 23'u8:
    return uint64(ai)
  elif ai == 24'u8:
    if pos + 1 > src.len: raise newException(CborEndOfBufferError, "need 1 byte")
    let v = uint64(src[pos])
    inc pos
    return v
  elif ai == 25'u8:
    if pos + 2 > src.len: raise newException(CborEndOfBufferError, "need 2 bytes")
    let v = (uint64(src[pos]) shl 8) or uint64(src[pos+1])
    pos += 2
    return v
  elif ai == 26'u8:
    if pos + 4 > src.len: raise newException(CborEndOfBufferError, "need 4 bytes")
    let v = (uint64(src[pos]) shl 24) or (uint64(src[pos+1]) shl 16) or (uint64(src[pos+2]) shl 8) or uint64(src[pos+3])
    pos += 4
    return v
  elif ai == 27'u8:
    if pos + 8 > src.len: raise newException(CborEndOfBufferError, "need 8 bytes")
    let v = (uint64(src[pos]) shl 56) or (uint64(src[pos+1]) shl 48) or (uint64(src[pos+2]) shl 40) or (uint64(src[pos+3]) shl 32) or
            (uint64(src[pos+4]) shl 24) or (uint64(src[pos+5]) shl 16) or (uint64(src[pos+6]) shl 8) or uint64(src[pos+7])
    pos += 8
    return v
  else:
    raise newException(CborInvalidArgError, "invalid additional info for uint argument")

proc decodeInt64*(src: openArray[byte], pos0: int = 0, consumed: var int): int64 =
  ## Decode a single top-level CBOR integer (major 0 or 1) starting at pos0.
  var pos = pos0
  if pos >= src.len: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = src[pos]
  inc pos
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  case major
  of mtUnsigned:
    let u = readUintArg(src, pos, ai)
    consumed = pos - pos0
    return int64(u)
  of mtNegative:
    let u = readUintArg(src, pos, ai)
    if u == high(uint64):
      raise newException(CborOverflowError, "negative int overflows int64")
    let v = -1'i64 - int64(u)
    consumed = pos - pos0
    return v
  else:
    raise newException(CborInvalidHeaderError, "not an integer header")

proc decodeBool*(src: openArray[byte], pos0: int = 0, consumed: var int): bool =
  ## Decode a single top-level CBOR boolean.
  var pos = pos0
  if pos >= src.len: raise newException(CborEndOfBufferError, "no bytes to read")
  let b0 = src[pos]
  inc pos
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  if major != mtSimple: raise newException(CborInvalidHeaderError, "not a simple value header")
  case ai
  of 20'u8: consumed = pos - pos0; false
  of 21'u8: consumed = pos - pos0; true
  else: raise newException(CborInvalidArgError, "not a bool simple value")
