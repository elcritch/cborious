import std/times
import std/strutils
import ./types
import ./stream
import ./cbor

# CBOR Timestamp helpers using Nim's std/times

const
  CborTagDateTimeString* = 0.CborTag
  CborTagEpochSeconds*   = 1.CborTag

proc cbor_tag*(tp: typedesc[DateTime]): CborTag =
  result = CborTagDateTimeString

proc cbor_tag*(tp: typedesc[Time]): CborTag =
  result = CborTagEpochSeconds

proc packTagged*[T](s: Stream, val: T) =
  ## Pack a value with a preceding tag.
  s.pack_tag(cbor_tag(T))
  s.pack_type(val)

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


proc packTimestampString*(s: Stream, dt: DateTime, fmt = "yyyy-MM-dd'T'HH:mm:sszzz") =
  ## Encode DateTime as tag(0) + RFC 3339 style string using provided format.
  ## Default includes timezone offset; ensure dt has correct zone.
  let txt = dt.format(fmt)
  s.packTagged(txt)

proc packTimestamp*(s: Stream, t: Time) =
  ## Encode Time as tag(1) + integer seconds since Unix epoch.
  let secs = t.toUnix
  s.packTagged(int64(secs))

proc unpackTimestampString*(s: Stream, fmt = "yyyy-MM-dd'T'HH:mm:sszzz", assumeZone: Timezone = utc()): DateTime =
  ## Decode tag(0) timestamp string into DateTime using provided format.
  ## If the format does not include an offset (no 'z'), the parsed DateTime is assigned assumeZone.
  var str: string
  s.unpackExpectTag(CborTagDateTimeString, str)
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
  result = dt

proc unpackTimestamp*(s: Stream): Time =
  ## Decode tag(1) integer seconds into Time.
  var secs: int64
  s.unpackExpectTag(CborTagEpochSeconds, secs)
  result = fromUnix(secs)
