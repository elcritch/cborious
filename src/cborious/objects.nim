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

import ./types
import ./stream
import ./cbor

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

template undistinct_pack*(x: typed): untyped =
  undistinctImpl(x, type(x), bindSym("pack_type", brForceOpen))

template undistinct_unpack*(x: typed): untyped =
  undistinctImpl(x, type(x), bindSym("unpack_type", brForceOpen))

proc unpack_type*[Stream; T: tuple|object](s: Stream, val: var T) =
  template dry_and_wet(): untyped =
    when defined(msgpack_obj_to_map):
      let len = s.unpack_map()
      var name: string
      var found: bool
      for i in 0..len-1:
        if not s.is_string:
          s.skip_item()
          s.skip_msg()
          continue
        s.cborUnpack(name)
        found = false
        for field, value in fieldPairs(val):
          if field == name:
            found = true
            s.cborUnpack(value)
            break
        if not found:
          s.skip_item()
    elif defined(msgpack_obj_to_stream):
      for field in fields(val):
        s.cborUnpack(field)
    else:
      let arrayLen = s.unpack_array()
      var length = 0
      for field in fields(val):
        s.cborUnpack(field)
        inc length
      doAssert(arrayLen == length, "object/tuple len mismatch")

  when Stream is CborStream:
    case s.encodingMode
    of CBOR_OBJ_TO_ARRAY:
      let arrayLen = s.unpack_array()
      var len = 0
      for field in fields(val):
        unpack_proxy(field)
        inc len
      doAssert(arrayLen == len, "object/tuple len mismatch")
    of CBOR_OBJ_TO_MAP:
      let len = s.unpack_map()
      var name: string
      var found: bool
      for i in 0..len-1:
        if not s.is_string:
          s.skip_item()
          s.skip_msg()
          continue
        unpack_proxy(name)
        found = false
        for field, value in fieldPairs(val):
          if field == name:
            found = true
            unpack_proxy(value)
            break
        if not found:
          s.skip_item()
    of CBOR_OBJ_TO_STREAM:
      for field in fields(val):
        unpack_proxy(field)
    else:
      dry_and_wet()
  else:
    dry_and_wet()
