# MessagePack implementation written in nim
#
# Copyright (c) 2015-2019 Andri Lim
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
#
#-------------------------------------

import std/macros
import std/algorithm

import ./types
import ./stream
import ./cbor

# ---- Distinct helpers (must appear before use) ----

proc getParamIdent(n: NimNode): NimNode =
  n.expectKind({nnkIdent, nnkVarTy, nnkSym})
  if n.kind in {nnkIdent, nnkSym}:
    result = n
  else:
    result = n[0]

proc hasDistinctImpl(w: NimNode, z: NimNode): bool =
  for k in w:
    let p = k.getImpl()[3][2][1]
    if p.kind in {nnkIdent, nnkVarTy, nnkSym}:
      let paramIdent = getParamIdent(p)
      if eqIdent(paramIdent, z): return true

proc needToSkip(typ: NimNode | typedesc, w: NimNode): bool {.compileTime.} =
  let z = getType(typ)[1]

  if z.kind == nnkSym:
    if hasDistinctImpl(w, z): return true

  if z.kind != nnkSym: return false
  let impl = getImpl(z)
  if impl.kind != nnkTypeDef: return false
  if impl[2].kind != nnkDistinctTy: return false
  if impl[0].kind != nnkPragmaExpr: return false
  let prag = impl[0][1][0]
  result = eqIdent("skipUndistinct", prag)

#this macro convert any distinct types to it's base type
macro undistinctImpl*(x: typed, typ: typedesc, w: typed): untyped =
  var ty = getType(x)
  if needToSkip(typ, w):
    result = x
    return
  var isDistinct = ty.typekind == ntyDistinct
  if isDistinct:
    let parent = ty[1]
    result = quote do: `parent`(`x`)
  else:
    result = x

template undistinctPack*(x: typed): untyped =
  undistinctImpl(x, type(x), bindSym("cborPack", brForceOpen))

template undistinctUnpack*(x: typed): untyped =
  undistinctImpl(x, type(x), bindSym("cborUnpack", brForceOpen))

# ---- Tag helpers ----

proc readOneTag*(s: Stream, tagOut: var CborTag): bool =
  ## Reads a single tag if present, returns true and sets tagOut. Restores position when not a tag.
  let pos = s.getPosition()
  let (m, ai) = s.readInitial()
  if m == CborMajor.Tag:
    tagOut = s.readAddInfo(ai).CborTag
    return true
  s.setPosition(pos)
  return false

proc unpackExpectTag*[T](s: Stream, tag: CborTag, value: var T) =
  ## Requires the next item to be a tag with the specified id, then unpacks a value of type T.
  let (m, ai) = s.readInitial()
  if m != CborMajor.Tag:
    raise newException(CborInvalidHeaderError, "expected tag")
  let t = s.readAddInfo(ai)
  if t != tag.uint64:
    raise newException(CborInvalidHeaderError, "unexpected tag value")
  s.cborUnpack(value)
# ---- Object and tuple encoding/decoding ----

template hasMode(s: Stream, m: EncodingMode): bool =
  (s of CborStream) and (m in CborStream(s).encodingMode)

proc cborPackObjectArray[T](s: Stream, val: T) {.inline.} =
  var len = 0
  for _ in fields(val): inc len
  cborPackInt(s, uint64(len), CborMajor.Array)
  for field in fields(val):
    s.cborPack undistinctPack(field)

proc cborPackObjectMap[T](s: Stream, val: T) {.inline.} =
  # Canonical map key ordering when using CborStream + CborCanonical
  when true:
    if s of CborStream and CborCanonical in CborStream(s).encodingMode:
      var items: seq[tuple[keyEnc: string, name: string, idx: int]] = @[]
      var i = 0
      for k, _ in fieldPairs(val):
        var ks = CborStream.init()
        ks.cborPack(k)
        items.add((move ks.data, k, i))
        inc i
      items.sort(proc(a, b: typeof(items[0])): int = cmp(a.keyEnc, b.keyEnc))
      cborPackInt(s, uint64(items.len), CborMajor.Map)
      for it in items:
        # write key encoding directly
        for ch in it.keyEnc: s.write(ch)
        # write value by field index order
        var j = 0
        for field in fields(val):
          if j == it.idx:
            s.cborPack undistinctPack(field)
            break
          inc j
      return
  # Non-canonical: preserve declaration order
  var len = 0
  for k, v in fieldPairs(val): inc len
  cborPackInt(s, uint64(len), CborMajor.Map)
  for k, v in fieldPairs(val):
    s.cborPack(k)
    s.cborPack undistinctPack(v)

proc cborPack*[T](s: Stream, val: T) =
  ## If a cborTag(T) is declared, serialize as tag(cborTag(T)) + cborPack(T).
  mixin cborTag
  when compiles(cborTag(T)):
    s.cborPackTag(cborTag(T))
    s.cborPack(val)
  else:
    s.cborPack(val)

proc cborPack*[T: tuple|object](s: Stream, val: T) =
  if s.hasMode(CborObjToMap):
    s.cborPackObjectMap(val)
  elif s.hasMode(CborObjToArray):
    s.cborPackObjectArray(val)
  elif s.hasMode(CborObjToStream):
    for field in fields(val):
      s.cborPack undistinctPack(field)
  else:
    # default to array for non-CborStream
    s.cborPackObjectArray(val)

proc cborUnpackObjectArray[T](s: Stream, val: var T) {.inline.} =
  let (major, ai) = s.readInitialSkippingTags()
  if major != CborMajor.Array:
    raise newException(CborInvalidHeaderError, "expected array for object/tuple")
  var count = 0
  for _ in fields(val): inc count
  if ai == AiIndef:
    # read exactly 'count' items then expect break
    var i = 0
    for field in fields(val):
      s.cborUnpack undistinctUnpack(field)
      inc i
    # consume break
    let b = s.readChar()
    if uint8(ord(b)) != 0xff'u8:
      raise newException(CborInvalidHeaderError, "missing break in indefinite array")
  else:
    let n = int(s.readAddInfo(ai))
    if n != count:
      raise newException(CborInvalidHeaderError, "object/tuple len mismatch")
    for field in fields(val):
      s.cborUnpack undistinctUnpack(field)

proc cborUnpackObjectMap[T](s: Stream, val: var T) {.inline.} =
  let (major, ai) = s.readInitialSkippingTags()
  if major != CborMajor.Map:
    raise newException(CborInvalidHeaderError, "expected map for object/tuple")
  # Build name->field setter closures via iteration over fields
  template assignField(name: string) =
    var i = 0
    for k, v in fieldPairs(val):
      if k == name:
        s.cborUnpack undistinctUnpack(v)
        break
      inc i
  if ai == AiIndef:
    while true:
      let pos = s.getPosition()
      let b = s.readChar()
      if uint8(ord(b)) == 0xff'u8: break
      s.setPosition(pos)
      var key: string
      s.cborUnpack(key)
      # if unknown, skip value
      var matched = false
      var i = 0
      for k, v in fieldPairs(val):
        if k == key:
          s.cborUnpack undistinctUnpack(v)
          matched = true
          break
        inc i
      if not matched:
        s.skipCborMsg()
  else:
    let n = int(s.readAddInfo(ai))
    var i = 0
    while i < n:
      var key: string
      s.cborUnpack(key)
      var matched = false
      for k, v in fieldPairs(val):
        if k == key:
          s.cborUnpack undistinctUnpack(v)
          matched = true
          break
      if not matched:
        s.skipCborMsg()
      inc i

proc cborUnpack*[T](s: Stream, val: var T) =
  ## If a cborTag(T) is declared, require and consume the tag before unpacking T.
  mixin cborTag
  when compiles(cborTag(T)):
    s.unpackExpectTag(cborTag(T), val)
  else:
    s.cborUnpack(val)

proc cborUnpack*[T: tuple|object](s: Stream, val: var T) =
  let pos = s.getPosition()
  let (major, _) = s.readInitialSkippingTags()
  s.setPosition(pos)
  case major
  of CborMajor.Array:
    s.cborUnpackObjectArray(val)
  of CborMajor.Map:
    s.cborUnpackObjectMap(val)
  else:
    # stream style: decode fields directly in order
    for field in fields(val):
      s.cborUnpack undistinctUnpack(field)
 
