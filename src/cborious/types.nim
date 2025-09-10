## Core types and small utilities for CBORious
## Focused minimal surface for integers and booleans.

type
  CborMajor* = enum
    Unsigned = 0
    Negative = 1
    Binary   = 2
    String   = 3
    Array    = 4
    Map      = 5
    Tag      = 6
    Simple   = 7

  CborTag* = distinct uint64

  CborException* = object of CatchableError
  CborEndOfBufferError* = object of CborException
  CborInvalidHeaderError* = object of CborException
  CborInvalidArgError* = object of CborException
  CborOverflowError* = object of CborException


const
  AiIndef* = 31'u8

  # RFC 8949 §3.4.6 Self-Described CBOR (0xD9D9F7)
  SelfDescribeTagId* = 55799'u64

proc `==`*(a: CborTag, b: CborTag): bool {.borrow.}

proc `$`*(a: CborTag): string =
  "Tag(" & $a.uint64 & ")"

proc majorToPrefix*(major: CborMajor): int =
  ## mostly for helping humans to grok the shifted prefixes
  case major
  of Unsigned :0x00 # 0 \0
  of Negative : 0x20 # 1 \32
  of Binary   : 0x40 # 2 \64
  of String   : 0x60 # 3 \96
  of Array    : 0x80 # 4 \128
  of Map      : 0xA0 # 5 \160
  of Tag      : 0xC0 # 6 \192
  of Simple   : 0xE0 # 7 \224

proc majorToChar*(major: CborMajor): char =
  ## mostly for helping humans to grok the shifted prefixes
  case major
  of Unsigned : '\0' # 0
  of Negative : '\32' # 1
  of Binary   : '\64' # 2
  of String   : '\96' # 3
  of Array    : '\128' # 4
  of Map      : '\160' # 5
  of Tag      : '\192' # 6
  of Simple   : '\224' # 7
