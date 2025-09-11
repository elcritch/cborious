import std/[times, strformat, strutils, os]

# Compare round-trip CBOR serialization for:
# - cborious (this repo)
# - cbor_serialization (nim-cbor-serialization in deps/)

import cborious
import cbor_serialization

type
  Person = object
    id: int
    name: string
    active: bool
    scores: seq[int]

proc samplePerson(): Person =
  Person(
    id: 42,
    name: "Nim User",
    active: true,
    scores: @[1, 2, 3, 5, 8]
  )

proc benchCborious(iters: int): int64 =
  let p = samplePerson()
  let t0 = cpuTime()
  var decoded: Person
  var i = 0
  while i < iters:
    let enc = toCbor(p)            # string
    fromCbor(enc, decoded)         # decode into `decoded`
    inc i
  let dt = cpuTime() - t0
  result = int64(dt * 1_000_000_000)

proc benchCborSerialization(iters: int): int64 =
  let p = samplePerson()
  let t0 = cpuTime()
  var decoded: Person
  var i = 0
  while i < iters:
    let enc = encode(Cbor, p)      # seq[byte]
    decoded = decode(Cbor, enc, Person)
    inc i
  let dt = cpuTime() - t0
  result = int64(dt * 1_000_000_000)

when isMainModule:
  # Allow overriding iterations via env; default kept modest for CI speed.
  let iters = try:
    strutils.parseInt(getEnv("CBOR_BENCH_ITERS", "20000"))
  except ValueError:
    20000

  let p = samplePerson()
  let encCborious = toCbor(p)
  let encCborSer = encode(Cbor, p)

  echo &"Benchmarking with iters={iters}"
  echo &"cborious:        one-shot size={encCborious.len} bytes"
  echo &"cbor_serialization: one-shot size={encCborSer.len} bytes"

  let tCborious = benchCborious(iters)
  let tCborSer  = benchCborSerialization(iters)

  proc fmt(ns: int64): string =
    let ms = ns div 1_000_000
    let us = (ns div 1_000) mod 1_000
    &"{ms}ms {us}us"

  echo "--- Results (encode + decode round-trip) ---"
  echo &"cborious:            total={fmt(tCborious)}  avg={(tCborious div iters)} ns/op"
  echo &"cbor_serialization:  total={fmt(tCborSer)}   avg={(tCborSer div iters)} ns/op"
