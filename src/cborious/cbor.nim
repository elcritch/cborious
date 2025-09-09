import ./types
import ./stream
import std/tables
import std/algorithm

# ---- CBOR core encode/decode (ints, bools) ----

template writeInitial*(s: Stream, major: CborMajor, ai: uint8) =
  s.write(char(((uint8(major) shl 5) or (ai and 0x1f))))

# Encode unsigned integer (major type 0)
proc cborPackInt*(s: Stream, v: uint64, maj: CborMajor) =
  if v <= 23'u64:
    s.writeInitial(maj, uint8(v))
  elif v <= 0xff'u64:
    s.writeInitial(maj, 24'u8)
    s.write(char(uint8(v)))
  elif v <= 0xffff'u64:
    s.writeInitial(maj, 25'u8)
    s.store16(uint16(v))
  elif v <= 0xffff_ffff'u64:
    s.writeInitial(maj, 26'u8)
    s.store32(uint32(v))
  else:
    s.writeInitial(maj, 27'u8)
    s.store64(v)

# Public pack_type overloads
proc pack_type*(s: Stream, val: bool) =
  writeInitial(s, CborMajor.Simple, uint8(val) + 20'u8)

proc pack_type*(s: Stream, val: uint64) = cborPackInt(s, val, CborMajor.Unsigned)
proc pack_type*(s: Stream, val: uint32) = cborPackInt(s, uint64(val), CborMajor.Unsigned)
proc pack_type*(s: Stream, val: uint16) = cborPackInt(s, uint64(val), CborMajor.Unsigned)
proc pack_type*(s: Stream, val: uint8)  = cborPackInt(s, uint64(val), CborMajor.Unsigned)
proc pack_type*(s: Stream, val: uint)   = cborPackInt(s, uint64(val), CborMajor.Unsigned)

proc pack_type*(s: Stream, val: int64) =
  if val >= 0:
    cborPackInt(s, uint64(val), CborMajor.Unsigned)
  else:
    cborPackInt(s, uint64(-1'i64 - val), CborMajor.Negative)

proc pack_type*(s: Stream, val: int32) = pack_type(s, int64(val))
proc pack_type*(s: Stream, val: int16) = pack_type(s, int64(val))
proc pack_type*(s: Stream, val: int8)  = pack_type(s, int64(val))
proc pack_type*(s: Stream, val: int)   = pack_type(s, int64(val))


# ---- Decoding ----

proc readInitial*(s: Stream): tuple[major: CborMajor, ai: uint8] =
  let b = uint8(ord(s.readChar()))
  result.major = CborMajor(b shr 5)
  result.ai = b and 0x1f

proc readAddInfo*(s: Stream, ai: uint8): uint64 =
  ## Decode the additional info for integers (0..27), return value.
  if ai < 24'u8:
    result = uint64(ai)
  elif ai == 24'u8:
    result = uint64(uint8(s.readChar()))
  elif ai == 25'u8:
    result = uint64(s.unstore16())
  elif ai == 26'u8:
    result = uint64(s.unstore32())
  elif ai == 27'u8:
    result = s.unstore64()
  else:
    raise newException(CborInvalidHeaderError, "invalid integer additional info")

proc unpack_type*(s: Stream, val: var bool) =
  let (major, ai) = s.readInitial()
  if major != CborMajor.Simple:
    raise newException(CborInvalidHeaderError, "expected simple value")
  case ai
  of 20'u8: val = false
  of 21'u8: val = true
  else:
    raise newException(CborInvalidHeaderError, "expected CBOR bool")

proc unpack_type*(s: Stream, val: var uint64) =
  let (major, ai) = s.readInitial()
  if major != CborMajor.Unsigned:
    raise newException(CborInvalidHeaderError, "expected unsigned integer")
  val = s.readAddInfo(ai)

proc unpack_type*(s: Stream, val: var int64) =
  let (major, ai) = s.readInitial()
  case major
  of CborMajor.Unsigned:
    let u = s.readAddInfo(ai)
    if u > uint64(high(int64)):
      raise newException(CborOverflowError, "uint does not fit int64")
    val = int64(u)
  of CborMajor.Negative:
    let n = s.readAddInfo(ai)
    if n == uint64(high(uint64)):
      # can't represent - (n+1) when n == max uint64
      raise newException(CborOverflowError, "negative integer overflow")
    let tmp = int64(n)
    if tmp == high(int64):
      # would underflow; safeguard
      raise newException(CborOverflowError, "negative integer overflow")
    val = - (int64(n) + 1'i64)
  else:
    raise newException(CborInvalidHeaderError, "expected integer (major 0 or 1)")

proc unpack_type*(s: Stream, val: var int32) =
  var x: int64
  s.unpack_type(x)
  if x < low(int32) or x > high(int32):
    raise newException(CborOverflowError, "int32 overflow")
  val = int32(x)

proc unpack_type*(s: Stream, val: var int16) =
  var x: int64
  s.unpack_type(x)
  if x < low(int16) or x > high(int16):
    raise newException(CborOverflowError, "int16 overflow")
  val = int16(x)

proc unpack_type*(s: Stream, val: var int8) =
  var x: int64
  s.unpack_type(x)
  if x < low(int8) or x > high(int8):
    raise newException(CborOverflowError, "int8 overflow")
  val = int8(x)

proc unpack_type*(s: Stream, val: var int) =
  when sizeof(int) == 8:
    var x64: int64
    s.unpack_type(x64)
    val = int(x64)
  else:
    var x32: int32
    s.unpack_type(x32)
    val = int(x32)

proc unpack_type*(s: Stream, val: var uint32) =
  var x: uint64
  s.unpack_type(x)
  if x > uint64(high(uint32)):
    raise newException(CborOverflowError, "uint32 overflow")
  val = uint32(x)

proc unpack_type*(s: Stream, val: var uint16) =
  var x: uint64
  s.unpack_type(x)
  if x > uint64(high(uint16)):
    raise newException(CborOverflowError, "uint16 overflow")
  val = uint16(x)

proc unpack_type*(s: Stream, val: var uint8) =
  var x: uint64
  s.unpack_type(x)
  if x > uint64(high(uint8)):
    raise newException(CborOverflowError, "uint8 overflow")
  val = uint8(x)

proc unpack_type*(s: Stream, val: var uint) =
  when sizeof(uint) == 8:
    var x64: uint64
    s.unpack_type(x64)
    val = uint(x64)
  else:
    var x32: uint32
    s.unpack_type(x32)
    val = uint(x32)


# ---- Binary (byte string), Text (UTF-8 string), and Arrays ----

proc packLen(s: Stream, len: int, maj: CborMajor) {.inline.} =
  if len < 0: raise newException(CborInvalidArgError, "negative length")
  cborPackInt(s, uint64(len), maj)

# Binary (major type 2): seq/array of uint8
proc pack_type*(s: Stream, val: openArray[uint8]) =
  s.packLen(val.len, CborMajor.Binary)
  if val.len > 0:
    var i = 0
    while i < val.len:
      s.write(char(val[i]))
      inc i

proc pack_type*(s: Stream, val: seq[uint8]) = s.pack_type(val.toOpenArray(0, val.high))

# Text string (major type 3)
proc pack_type*(s: Stream, val: string) =
  s.packLen(val.len, CborMajor.String)
  if val.len > 0:
    for ch in val:
      s.write(ch)

# Array (major type 4)
proc pack_type*[T](s: Stream, val: openArray[T]) =
  s.packLen(val.len, CborMajor.Array)
  for it in val:
    s.pack_type(it)

proc pack_type*[T](s: Stream, val: seq[T]) = s.pack_type(val.toOpenArray(0, val.high))

# Map (major type 5)
proc pack_type*[K, V](s: Stream, val: Table[K, V]) =
  # Canonical only when using CborStream (msgpack4nim-style stream check)
  if s of CborStream:
    var items: seq[tuple[keyEnc: string, k: K, v: V]]
    items.setLen(0)
    for k, v in val.pairs:
      var ks = CborStream.init()
      ks.pack_type(k)
      items.add((move ks.data, k, v))
    items.sort(proc(a, b: typeof(items[0])): int = cmp(a.keyEnc, b.keyEnc))
    s.packLen(items.len, CborMajor.Map)
    for it in items:
      for ch in it.keyEnc: s.write(ch)
      s.pack_type(it.v)
  else:
    s.packLen(val.len, CborMajor.Map)
    for k, v in val.pairs:
      s.pack_type(k)
      s.pack_type(v)

proc pack_type*[K, V](s: Stream, val: OrderedTable[K, V]) =
  if s of CborStream:
    var items: seq[tuple[keyEnc: string, k: K, v: V]]
    items.setLen(0)
    for k, v in val.pairs:
      var ks = CborStream.init()
      ks.pack_type(k)
      items.add((move ks.data, k, v))
    items.sort(proc(a, b: typeof(items[0])): int = cmp(a.keyEnc, b.keyEnc))
    s.packLen(items.len, CborMajor.Map)
    for it in items:
      for ch in it.keyEnc: s.write(ch)
      s.pack_type(it.v)
  else:
    s.packLen(val.len, CborMajor.Map)
    for k, v in val.pairs:
      s.pack_type(k)
      s.pack_type(v)


# ---- Decoding helpers ----

proc readChunk(s: Stream, majExpected: CborMajor, ai: uint8): string =
  ## Reads binary/text data handling definite and indefinite lengths.
  if ai == aiIndef:
    # Indefinite-length: concatenate definite-length chunks until break 0xff
    var acc = ""
    while true:
      let pos = s.getPosition()
      let b = s.readChar()
      if uint8(ord(b)) == 0xff'u8: # break
        break
      s.setPosition(pos)
      let (m2, ai2) = s.readInitial()
      if m2 != majExpected or ai2 == aiIndef:
        raise newException(CborInvalidHeaderError, "invalid chunk in indefinite string")
      let n = int(s.readAddInfo(ai2))
      if n < 0: raise newException(CborInvalidHeaderError, "negative length")
      let part = s.readExactStr(n)
      acc.add(part)
    return acc
  else:
    let n = int(s.readAddInfo(ai))
    if n < 0: raise newException(CborInvalidHeaderError, "negative length")
    return s.readExactStr(n)

# ---- Decoding for new types ----

proc unpack_type*(s: Stream, val: var seq[byte]) =
  let (major, ai) = s.readInitial()
  if major != CborMajor.Binary:
    raise newException(CborInvalidHeaderError, "expected binary string")
  let data = s.readChunk(CborMajor.Binary, ai)
  val.setLen(data.len)
  var i = 0
  for ch in data:
    val[i] = uint8(ord(ch))
    inc i

proc unpack_type*(s: Stream, val: var string) =
  let (major, ai) = s.readInitial()
  if major != CborMajor.String:
    raise newException(CborInvalidHeaderError, "expected text string")
  val = s.readChunk(CborMajor.String, ai)

proc unpack_type*[T](s: Stream, val: var seq[T]) =
  let (major, ai) = s.readInitial()
  if major != CborMajor.Array:
    raise newException(CborInvalidHeaderError, "expected array")
  if ai == aiIndef:
    # Grow until break
    val.setLen(0)
    while true:
      let pos = s.getPosition()
      let b = s.readChar()
      if uint8(ord(b)) == 0xff'u8: break
      s.setPosition(pos)
      var item: T
      s.unpack_type(item)
      val.add(item)
  else:
    let n = int(s.readAddInfo(ai))
    if n < 0: raise newException(CborInvalidHeaderError, "negative length")
    val.setLen(n)
    var i = 0
    while i < n:
      s.unpack_type(val[i])
      inc i

type SomeMap[K, V] = Table[K, V] | OrderedTable[K, V]

proc unpack_type_impl*[K, V](s: Stream, val: var SomeMap[K, V]) =
  let (major, ai) = s.readInitial()
  if major != CborMajor.Map:
    raise newException(CborInvalidHeaderError, "expected map")
  val.clear()
  if ai == aiIndef:
    while true:
      let pos = s.getPosition()
      let b = s.readChar()
      if uint8(ord(b)) == 0xff'u8: break
      s.setPosition(pos)
      var k: K
      var v: V
      s.unpack_type(k)
      s.unpack_type(v)
      val[k] = v
  else:
    let n = int(s.readAddInfo(ai))
    if n < 0: raise newException(CborInvalidHeaderError, "negative length")
    var i = 0
    while i < n:
      var k: K
      var v: V
      s.unpack_type(k)
      s.unpack_type(v)
      val[k] = v
      inc i

proc unpack_type*[K, V](s: Stream, val: var Table[K, V]) =
  s.unpack_type_impl(val)

proc unpack_type*[K, V](s: Stream, val: var OrderedTable[K, V]) =
  s.unpack_type_impl(val)
