import std/times
import std/strutils
import ./types
import ./stream
import ./cbor

# CBOR Timestamp helpers using Nim's std/times

const
  CborTagDateTimeString* = 0.CborTag
  CborTagEpochSeconds*   = 1.CborTag

proc cborTag*(tp: typedesc[DateTime]): CborTag =
  result = CborTagDateTimeString

proc cborTag*(tp: typedesc[Time]): CborTag =
  result = CborTagEpochSeconds

proc pack_tagged*[T](s: Stream, val: T) =
  ## Pack a value with a preceding tag.
  s.pack_tag(cborTag(T))
  s.pack_tagged(val)

proc readOneTag*(s: Stream, tagOut: var CborTag): bool =
  ## Reads a single tag if present, returns true and sets tagOut. Restores position when not a tag.
  let pos = s.getPosition()
  let (m, ai) = s.readInitial()
  if m == CborMajor.Tag:
    tagOut = s.readAddInfo(ai).CborTag
    return true
  s.setPosition(pos)
  return false

proc unpackExpectTag*[T](s: Stream, value: var T) =
  ## Requires the next item to be a tag with the specified id, then unpacks a value of type T.
  let (m, ai) = s.readInitial()
  if m != CborMajor.Tag:
    raise newException(CborInvalidHeaderError, "expected tag")
  let t = s.readAddInfo(ai)
  if t != cborTag(T).uint64:
    raise newException(CborInvalidHeaderError, "unexpected tag value")
  s.unpack_type(value)

const datetimeFmt = "yyyy-MM-dd'T'HH:mm:sszzz"
var assumeZone: Timezone = utc()

proc pack_tagged*(s: Stream, dt: DateTime) =
  ## Encode DateTime as tag(0) + RFC 3339 style string using provided format.
  ## Default includes timezone offset; ensure dt has correct zone.
  let txt = dt.format(datetimeFmt)
  s.pack_type(txt)

proc pack_tagged*(s: Stream, t: Time) =
  ## Encode Time as tag(1) + integer seconds since Unix epoch.
  let secs = t.toUnix
  s.pack_type(int64(secs))

proc unpack_tagged*(s: Stream, dt: var DateTime) =
  ## Decode tag(0) timestamp string into DateTime using provided format.
  ## If the format does not include an offset (no 'z'), the parsed DateTime is assigned assumeZone.
  var str: string
  s.unpackExpectTag(str)
  var dt: DateTime
  if 'z' in fmt:
    dt = parse(str, fmt)
  elif "'Z'" in fmt:
    let fmt2 = fmt.replace("'Z'", "zzz")
    let str2 = str.replace("Z", "+00:00")
    dt = parse(str2, fmt2)
  else:
    let tmp = parse(str, fmt)
    dt = initDateTime(tmp.monthday, tmp.month, tmp.year, tmp.hour, tmp.minute, tmp.second, zone = assumeZone)
  dt = dt

proc unpack_tagged*(s: Stream, t: var Time) =
  ## Decode tag(1) integer seconds into Time.
  var secs: int64
  s.unpackExpectTag(secs)
  t = fromUnix(secs)
