
proc halfToFloat32*(bits: uint16): float32 =
  ## Convert IEEE-754 half-precision to float32.
  let sgn = (bits shr 15) and 0x1'u16
  let e = (bits shr 10) and 0x1F'u16
  let f = bits and 0x3FF'u16
  if e == 0x1F'u16:
    # Inf / NaN
    let sign = uint32(sgn) shl 31
    let frac32 = uint32(f) shl 13
    let exp32 = 0xFF'u32 shl 23
    return cast[float32](sign or exp32 or frac32)
  elif e == 0'u16:
    if f == 0'u16:
      # signed zero
      let sign = uint32(sgn) shl 31
      return cast[float32](sign)
    else:
      # subnormal: value = (-1)^s * f * 2^-24
      let signMul = (if sgn == 0'u16: 1.0'f32 else: -1.0'f32)
      return signMul * float32(f) * (1.0'f32 / float32(1 shl 24))
  else:
    # normal number
    let sign = uint32(sgn) shl 31
    let exp32 = uint32(uint16(e + 112'u16)) shl 23 # 127-15 = 112 bias delta
    let frac32 = uint32(f) shl 13
    return cast[float32](sign or exp32 or frac32)

proc float32ToHalfBits*(v: float32): uint16 =
  ## Convert float32 to IEEE-754 half with round-to-nearest-even.
  let x = cast[uint32](v)
  let sign = (x shr 16) and 0x8000'u32
  let mant = x and 0x7fffff'u32
  let exp = (x shr 23) and 0xff'u32
  if exp == 0xff'u32: # NaN/Inf
    if mant == 0'u32: return uint16(sign or 0x7c00'u32) # Inf
    return uint16(sign or 0x7e00'u32) # qNaN canonical
  var e = int32(exp) - 127 + 15
  if e >= 31:
    return uint16(sign or 0x7c00'u32) # overflow -> Inf
  if e <= 0:
    if e < -10: return uint16(sign) # underflow -> zero
    var m = mant or 0x800000'u32
    let shift = uint32(14 - e)
    var mant2 = m shr (shift - 1)
    mant2 = mant2 + (mant2 and 1'u32) # round to even
    return uint16(sign or (mant2 shr 1))
  var mant2 = mant + 0x1000'u32 # add rounding bias
  if (mant2 and 0x800000'u32) != 0'u32:
    mant2 = 0
    inc e
  if e >= 31: return uint16(sign or 0x7c00'u32)
  return uint16(sign or (uint32(e) shl 10) or (mant2 shr 13))
