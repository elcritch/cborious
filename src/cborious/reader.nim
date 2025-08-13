import types

{.push checks: off.}

proc readUintArg(src: openArray[byte], pos: var int, ai: uint8, outv: var uint64): CborError =
  ## Read the unsigned argument value according to additional info `ai`.
  if ai <= 23'u8:
    outv = uint64(ai)
    return ceNone
  elif ai == 24'u8:
    if pos + 1 > src.len: return ceEndOfBuffer
    outv = uint64(src[pos])
    inc pos
    return ceNone
  elif ai == 25'u8:
    if pos + 2 > src.len: return ceEndOfBuffer
    outv = (uint64(src[pos]) shl 8) or uint64(src[pos+1])
    pos += 2
    return ceNone
  elif ai == 26'u8:
    if pos + 4 > src.len: return ceEndOfBuffer
    outv = (uint64(src[pos]) shl 24) or (uint64(src[pos+1]) shl 16) or (uint64(src[pos+2]) shl 8) or uint64(src[pos+3])
    pos += 4
    return ceNone
  elif ai == 27'u8:
    if pos + 8 > src.len: return ceEndOfBuffer
    outv = (uint64(src[pos]) shl 56) or (uint64(src[pos+1]) shl 48) or (uint64(src[pos+2]) shl 40) or (uint64(src[pos+3]) shl 32) or
           (uint64(src[pos+4]) shl 24) or (uint64(src[pos+5]) shl 16) or (uint64(src[pos+6]) shl 8) or uint64(src[pos+7])
    pos += 8
    return ceNone
  else:
    return ceInvalidArg

proc decodeInt64*(src: openArray[byte], pos0: int = 0, consumed: var int): (int64, CborError) =
  ## Decode a single top-level CBOR integer (major 0 or 1) starting at pos0.
  var pos = pos0
  if pos >= src.len: return (0'i64, ceEndOfBuffer)
  let b0 = src[pos]
  inc pos
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  var u: uint64
  case major
  of mtUnsigned:
    let err = readUintArg(src, pos, ai, u)
    if err != ceNone: return (0'i64, err)
    consumed = pos - pos0
    return (int64(u), ceNone)
  of mtNegative:
    let err = readUintArg(src, pos, ai, u)
    if err != ceNone: return (0'i64, err)
    if u == high(uint64):
      # Would overflow int64 when computing -1 - u
      return (0'i64, ceOverflow)
    let v = -1'i64 - int64(u)
    consumed = pos - pos0
    return (v, ceNone)
  else:
    return (0'i64, ceInvalidHeader)

proc decodeBool*(src: openArray[byte], pos0: int = 0, consumed: var int): (bool, CborError) =
  ## Decode a single top-level CBOR boolean.
  var pos = pos0
  if pos >= src.len: return (false, ceEndOfBuffer)
  let b0 = src[pos]
  inc pos
  let major = CborMajor((b0 shr 5) and 0x7)
  let ai = uint8(b0 and 0x1f)
  if major != mtSimple: return (false, ceInvalidHeader)
  case ai
  of 20'u8: consumed = pos - pos0; (false, ceNone)
  of 21'u8: consumed = pos - pos0; (true, ceNone)
  else: (false, ceInvalidArg)

