import std/times
import ./types
import ./stream
import ./cbor
import ./objects

export times, objects

# CBOR Tag helpers with opt-in tagging via cborTag(T)

proc cborTag*(tp: typedesc[DateTime]): CborTag =
  result = 0.CborTag

proc cborTag*(tp: typedesc[Time]): CborTag =
  result = 1.CborTag

proc cborTag*[T](tp: typedesc[set[T]]): CborTag =
  result = 258.CborTag

proc cborPack*(s: Stream, val: DateTime) =
  let isoDate = val.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  s.cborPackTag(cborTag(DateTime))
  s.cborPack(isoDate)

proc cborUnpack*(s: Stream, val: var DateTime) =
  var isoDate: string
  s.cborExpectTag(cborTag(DateTime))
  s.cborUnpack(isoDate)
  val = parse(isoDate, "yyyy-MM-dd'T'HH:mm:ss'Z'")

proc cborPack*(s: Stream, val: Time) =
  let epoch = val.toUnix()
  s.cborPackTag(cborTag(DateTime))
  s.cborPack(epoch)

proc cborUnpack*(s: Stream, val: var Time) =
  var epoch: int64
  s.cborExpectTag(cborTag(Time))

  let pos = s.getPosition()
  let (major, ai) = s.readInitial()
  s.setPosition(pos)

  case major
  of CborMajor.Unsigned:
    var tmp: uint64
    s.cborUnpack(tmp)
    val = fromUnix(cast[int64](tmp))
  of CborMajor.Negative:
    var tmp: int64
    s.cborUnpack(tmp)
    val = fromUnix(tmp)
  of CborMajor.Simple:
    var tmp: float64
    s.cborUnpack(tmp)
    val = fromUnixFloat(tmp)
  else:
    raise newException(CborInvalidHeaderError, "expected unix time as an int or float but got " & $major)
