import std/times
import std/strutils
import ./types
import ./stream
import ./cbor
import ./objects

export times, objects

# CBOR Tag helpers with opt-in tagging via cborTag(T)

const
  CborTagDateTimeString* = 0.CborTag

proc cborTag*(tp: typedesc[DateTime]): CborTag =
  result = CborTagDateTimeString

# proc cborTag*(tp: typedesc[Time]): CborTag =
#   result = CborTagEpochSeconds

proc cborPack*(s: Stream, val: DateTime) =
  ## If a cborTag(T) is declared, serialize as tag(cborTag(T)) + cborPack(T).
  let isoDate = val.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  s.cborPackTag(cborTag(DateTime))
  s.cborPack(isoDate)

proc cborUnpack*(s: Stream, val: var DateTime) =
  ## If a cborTag(T) is declared, require and consume the tag before unpacking T.
  var isoDate: string
  s.cborExpectTag(cborTag(DateTime))
  s.cborUnpack(isoDate)
  val = parse(isoDate, "yyyy-MM-dd'T'HH:mm:ss'Z'")
