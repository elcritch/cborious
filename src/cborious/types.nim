## Core types and small utilities for CBORious
## Focused minimal surface for integers and booleans.

type
  CborMajor* = enum
    mtUnsigned = 0
    mtNegative = 1
    mtBstr     = 2
    mtTstr     = 3
    mtArray    = 4
    mtMap      = 5
    mtTag      = 6
    mtSimple   = 7

  CborException* = object of CatchableError
  CborEndOfBufferError* = object of CborException
  CborInvalidHeaderError* = object of CborException
  CborInvalidArgError* = object of CborException
  CborOverflowError* = object of CborException

const
  aiIndef* = 31'u8
