# CBORious

CBORious is a fast, standards-compliant CBOR (Concise Binary Object Representation) library for Nim 2.x. It offers streaming, deterministic and canonical encodings, and compile-time derivation of serializers inspired by msgpack4nim.

## Features
- Streaming reader and writer
- Deterministic and canonical encoding modes following [RFC 8949](docs/rfc8949.md)
- Compile-time encode/decode derivation for Nim types
- Liberal decode mode for interoperability

## Installation
Requires Nim >= 2.0.14.

```bash
nimble install cborious # when published
# or for development
atlas install
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

