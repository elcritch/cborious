# CBORious

CBORious is a fast, standards-compliant CBOR (Concise Binary Object Representation) library for Nim 2.x. It offers streaming, deterministic and canonical encodings, and compile-time derivation of serializers inspired by msgpack4nim.

If you're unfamiliar with CBOR checkout the [CBOR Book](https://cborbook.com/introduction/introduction.html)!

## Features
- Streaming reader and writer
- Deterministic and canonical encoding modes following [RFC 8949](docs/rfc8949.md)
- Compile-time encode/decode derivation for Nim types
- Liberal decode mode for interoperability
- Tag Extension Support

### Tag Extensions

- DateTime and Timestamp 
- Typed Arrays: [RFC8746](https://www.ietf.org/rfc/rfc8746.html)

## Installation
Requires Nim >= 2.0.14.

```bash
atlas use https://github.com/elcritch/cborious 
nimble install https://github.com/elcritch/cborious 
```

## Usage
Encode and decode values using the high-level helpers:

```nim
import cborious

type Msg = object
  greeting: string
  value: int

let enc = toCbor(Msg(greeting: "hi", value: 42))
let dec = fromCbor(enc, Msg)
assert dec.value == 42
```

### Streaming with `CborStream`

Use `CborStream` for incremental reads and writes with `pack` and `unpack`:

```nim
import cborious

var s = CborStream.init()
let data = [1, 2, 3]
pack(s, data)           # encode into the stream's buffer
s.setPosition(0)        # rewind for reading
let out = unpack(s, seq[int])
assert out == data
```

### Tags

CBOR tags attach semantic meaning to the next value. Types can define a
`cborTag` proc to associate a numeric tag with the type; the tag is emitted on
encode and verified or skipped on decode. Unknown tags are ignored.

Checkout the [IANA CBOR Tags](https://www.iana.org/assignments/cbor-tags/cbor-tags.xhtml).

```nim
import cborious

type Foo = object
  bar: int

proc cborTag(_: typedesc[Foo]): CborTag = 3.CborTag

var cs = CborStream.init()
pack(cs, Foo(bar: 7))
cs.setPosition(0)
let foo = unpack(cs, Foo)
assert foo.bar == 7
```

### Encoding properties

`EncodingMode` flags control how values are written or read. The default is
`{CborObjToArray, CborCheckHoleyEnums}`:

- `CborObjToArray`: encode Nim objects as positional arrays
- `CborObjToMap`: encode Nim objects as maps with string keys
- `CborObjToStream`: emit object fields sequentially without a container for streaming
- `CborCanonical`: enforce RFC 8949 canonical form (minimal encodings, sorted map keys)
- `CborEnumAsString`: encode enums by name instead of ordinal
- `CborCheckHoleyEnums`: reject undefined enum values during decode
- `CborSelfDescribe`: prefix the self-describe CBOR tag (55799)

## Testing
Run the full test suite:

```bash
nim test
```

## Documentation
Generate API docs into `docs/api`:

```bash
nim docs
```

## License
Licensed under the Apache-2.0 license. See `cborious.nimble` for details.

## Benchmarks

How Cborious stacks up to other Nim based CBOR libraries:

```sh
> nim c -d:release -r tests/bench_cbor.nim
cborious:           one-shot size=41 bytes repr=@[164, 98, 105, 100, 24, 42, 100, 110, 97, 109, 101, 104, 78, 105, 109, 32, 85, 115, 101, 114, 102, 97, 99, 116, 105, 118, 101, 245, 102, 115, 99, 111, 114, 101, 115, 133, 1, 2, 3, 5, 8]
cbor_serialization: one-shot size=41 bytes repr=@[164, 98, 105, 100, 24, 42, 100, 110, 97, 109, 101, 104, 78, 105, 109, 32, 85, 115, 101, 114, 102, 97, 99, 116, 105, 118, 101, 245, 102, 115, 99, 111, 114, 101, 115, 133, 1, 2, 3, 5, 8]
cbor_em:            one-shot size=41 bytes repr=@[164, 98, 105, 100, 24, 42, 100, 110, 97, 109, 101, 104, 78, 105, 109, 32, 85, 115, 101, 114, 102, 97, 99, 116, 105, 118, 101, 245, 102, 115, 99, 111, 114, 101, 115, 133, 1, 2, 3, 5, 8]
--- Results (encode + decode round-trip) ---
cborious:              avg=61787 ns/op total=617 ms
cbor_serialization:    avg=111621 ns/op total=1116 ms
cbor_em:               avg=107082 ns/op total=1070 ms

cbor_serialization/cborious: 1.81x for 10000 iterations
cbor_em/cborious: 1.73x for 10000 iterations
```

They're all pretty fast but Cborious has a bit of a lead!

