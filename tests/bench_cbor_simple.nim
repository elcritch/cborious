import std/[monotimes, times, strformat, strutils, os, sequtils, math]

# Compare round-trip CBOR serialization for:
# - cborious (this repo)
# - cbor_serialization (nim-cbor-serialization in deps/)

import cborious
import cbor_serialization
import cbor as cbor_em

type
  Person = (uint16, int16, bool, int, float64, float32, (int, int))

proc samplePerson(): Person =
  ( 42,  100,  true, 100, 2.71828, 3.1415, (1, 2) )

proc samplePeople(): seq[Person] =
  var p = samplePerson()
  var pps: seq[Person]
  for i in 1..100:
    p[0] = i.uint16
    pps.add(p)
  result = pps

template bench(blk: untyped): Duration =
  let t0 = getMonoTime()
  `blk`
  let dt = getMonoTime() - t0
  dt

proc benchCborious(iters: int): Duration =
  var pps = samplePeople()

  bench:
    var decoded: seq[Person]
    for i in 0..<iters:
      for p in pps.mitems: p[0] = i.uint16
      decoded.setLen(0)
      let enc = toCbor(pps, {})            # string
      fromCbor(enc, decoded)         # decode into `decoded`
      doAssert decoded.len == pps.len

proc benchCborSerialization(iters: int): Duration =
  var pps = samplePeople()

  bench:
    var decoded: seq[Person]
    for i in 0..<iters:
      for p in pps.mitems: p[0] = i.uint16
      decoded.setLen(0)
      let enc = encode(Cbor, pps)      # seq[byte]
      decoded = decode(Cbor, enc, seq[Person])
      doAssert decoded.len == pps.len

proc benchCborEm(iters: int): Duration =
  var pps = samplePeople()

  bench:
    for i in 0..<iters:
      for p in pps.mitems: p[0] = i.uint16
      let c = cbor_em.encode(pps)
      let cn = cbor_em.parseCbor(c)
      var decoded: seq[Person]
      discard fromCbor(decoded, cn)
      doAssert decoded.len == pps.len

when isMainModule:
  # Allow overriding iterations via env; default kept modest for CI speed.
  let iters = try:
    strutils.parseInt(getEnv("CBOR_BENCH_ITERS", "10_000"))
  except ValueError:
    20000

  let p = samplePerson()
  let encCborious = toCbor(p, {})
  let encCborSer = encode(Cbor, p)
  let encCborEm = cbor_em.encode(p)

  echo &"Benchmarking with iters={iters}"
  echo &"cborious:           one-shot size={encCborious.len} bytes repr={encCborious.toOpenArrayByte(0, encCborious.len-1).toSeq().repr}"
  echo &"cbor_serialization: one-shot size={encCborSer.len} bytes repr={encCborSer.repr}"
  echo &"cbor_em:            one-shot size={encCborEm.len} bytes repr={encCborEm.toOpenArrayByte(0, encCborEm.len-1).toSeq().repr}"

  let tCborious0 = benchCborious(iters)
  let tCborious = benchCborious(iters)
  let tCborSer0  = benchCborSerialization(iters)
  let tCborSer  = benchCborSerialization(iters)
  let tCborEm0  = benchCborEm(iters)
  let tCborEm  = benchCborEm(iters)

  let ratio = tCborSer.inNanoseconds().float / tCborious.inNanoseconds().float
  let ratioEm = tCborEm.inNanoseconds().float / tCborious.inNanoseconds().float

  echo "--- Results (encode + decode round-trip) ---"
  echo &"cborious:              avg={(tCborious.inNanoseconds() div iters)} ns/op total={$(tCborious.inMilliseconds())} ms"
  echo &"cbor_serialization:    avg={(tCborSer.inNanoseconds() div iters)}  ns/op total={$(tCborSer.inMilliseconds())} ms"
  echo &"cbor_em:               avg={(tCborEm.inNanoseconds() div iters)}  ns/op total={$(tCborEm.inMilliseconds())} ms"
  echo ""
  echo &"cbor_serialization/cborious: {ratio:.2f}x for {iters} iterations"
  echo &"cbor_em/cborious: {ratioEm:.2f}x for {iters} iterations"
