## Core types and small utilities for CBORious
## Focused minimal surface for integers and booleans.

import std/streams
import ./stream

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

  CborException* = object of CatchableError
  CborEndOfBufferError* = object of CborException
  CborInvalidHeaderError* = object of CborException
  CborInvalidArgError* = object of CborException
  CborOverflowError* = object of CborException

const
  aiIndef* = 31'u8
