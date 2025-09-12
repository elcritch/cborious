# Package

version       = "0.5.1"
author        = "Jaremy Creechley"
description   = "A new awesome nimble package"
license       = "Apache-2.0"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.14"

feature "benchmark":
  requires "https://github.com/elcritch/nim-cbor-serialization.git"
  requires "https://git.sr.ht/~ehmry/nim_cbor"
  requires "msgpack4nim"
