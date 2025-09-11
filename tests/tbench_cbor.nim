import std/[monotimes, times, strformat, strutils, os]

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

proc samplePeople(): seq[Person] =
  var p = samplePerson()
  var pps: seq[Person]
  for i in 1..100:
    p.id = i
    pps.add(p)

template bench(blk: untyped): Duration =
  let t0 = getMonoTime()
  `blk`
  let dt = getMonoTime() - t0
  dt

proc benchCborious(iters: int): Duration =
  let pps = samplePeople()

  bench:
    var decoded: seq[Person]
    for i in 0..<iters:
      decoded.setLen(0)
      let enc = toCbor(pps, {CborObjToMap})            # string
      fromCbor(enc, decoded)         # decode into `decoded`

proc benchCborSerialization(iters: int): Duration =
  let pps = samplePeople()

  bench:
    var decoded: seq[Person]
    for i in 0..<iters:
      decoded.setLen(0)
      let enc = encode(Cbor, pps)      # seq[byte]
      decoded = decode(Cbor, enc, seq[Person])

when isMainModule:
  # Allow overriding iterations via env; default kept modest for CI speed.
  let iters = try:
    strutils.parseInt(getEnv("CBOR_BENCH_ITERS", "80_000"))
  except ValueError:
    20000

  let p = samplePerson()
  let encCborious = toCbor(p, {CborObjToMap})
  let encCborSer = encode(Cbor, p)

  echo &"Benchmarking with iters={iters}"
  echo &"cborious:        one-shot size={encCborious.len} bytes"
  echo &"cbor_serialization: one-shot size={encCborSer.len} bytes"

  let tCborious0 = benchCborious(iters)
  let tCborSer0  = benchCborSerialization(iters)

  let tCborious = benchCborious(iters)
  let tCborSer  = benchCborSerialization(iters)

  echo "--- Results (encode + decode round-trip) ---"
  echo &"cborious:              avg={(tCborious.inNanoseconds() div iters)} ns/op total={$(tCborious)}"
  echo &"cbor_serialization:    avg={(tCborSer.inNanoseconds() div iters)}  ns/op total={$(tCborSer)}"
