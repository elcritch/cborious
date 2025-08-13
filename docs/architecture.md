# CBORious Architecture

Ultra-fast, standards-compliant CBOR for Nim 2.x, designed for zero-copy reads, deterministic/canonical encoding, and compile-time derivation of serializers using Nim’s macros/templates (inspired by deps/msgpack4nim). This document captures the design, public surface, performance strategy, and compliance choices, with cross-references to deps/cbor-x-js, deps/QCBOR, and RFC 8949.

## Goals
- Throughput and latency: match or exceed QCBOR-class performance in C while keeping Nim ergonomics.
- Zero-copy where safe: avoid allocations for reading byte/text strings and simple values.
- Predictable memory: bounded, stack-friendly, and arena-friendly options.
- Deterministic/canonical encoding modes: follow RFC 8949 requirements for Deterministic and Canonical CBOR.
- Nim-first ergonomics: compile-time derivation for objects/variants inspired by msgpack4nim patterns.
- Streaming: incremental reader/writer for large items and indefinite-length containers.
- Interop: accept common deviations in a “liberal decode” mode while defaulting to strict.

Non-goals
- Full schema system. We target lightweight deriving and hooks, not a full IDL.
- Full tag registry surface. We implement core tags and provide extension hooks.

## High-Level Design
- Core codecs: minimal, allocation-free primitives for each CBOR major type and argument encoding.
- Buffer model: operate on `openArray[byte]`/slices; writers can write to user-supplied buffers or a fast-growing `seq[byte]` using capacity growth heuristics.
- Readers and writers: stateful `CborReader` and `CborWriter` mirror QCBOR’s streaming design while exposing a Nim-idiomatic API.
- Typeclass-style derivation: compile-time generated `encode`/`decode` procs for Nim objects, seqs, arrays, tuples, enums, and sum types via templates/macros, patterned after deps/msgpack4nim’s use of Nim metaprogramming.
- Profiles: `Strict`, `LiberalDecode`, `Deterministic`, `Canonical`. Profiles influence validation, accepted inputs, and map key ordering.

## Core Data Model
- Major types: unsigned, negative, byte string, text string, array, map, tag, simple/float.
- Internal value cursors: small struct capturing `major`, `ai` (additional info), `lenOrVal`, `offset`, optional `tag` depth. Similar to QCBORItem but leaner.
- Tags: store a small stack (configurable depth) for nested tags; expose them to higher layers.

## Public API (draft)
- Encode: `encode(dst, value, cfg) -> int`, `encode(value, cfg) -> seq[byte]`, `CborWriter` with `startArray`, `startIndefArray`, `endContainer`, `write` for scalars.
- Decode: `decode(T, src, cfg) -> T`, `CborReader` with `init`, `next(item) -> bool`, `read[T](outv) -> bool`.
- Derivation: `deriveCbor(T)` generates `encode`/`decode`; field attributes via pragmas (see below).
- Options: `CborEncodeOptions` (`canonical`, `deterministic`, `sortKeys`, `omitDefaults`, `floatPrecision`), `CborDecodeOptions` (`strict`, `allowIndefinite`, `allowDuplicateKeys`, `textValidation`, `maxNesting`, `maxItemLen`).

## Fast Path Encoding/Decoding
- Integers: single branch for ai ≤ 23; fall through to 1/2/4/8-byte encodings. Use unchecked shifts; assert in debug; disable bounds checks in hot regions.
- Short strings: inline header + memcopy; ASCII fast path for text validation if enabled.
- Arrays/Maps: known-size path writes header once; indefinite-length fallbacks for streaming.
- Floats: encode as half/float/double per options; prefer smallest that round-trips if deterministic.
- Tags: one or two tag headers before the value; avoid heap where possible.

Implementation notes
- Nim primitives: `copyMem`, `moveMem`, `cast[ptr UncheckedArray[byte]]`, `system.endians`; `unsafeAddr` for in-place numeric encoding.
- Maintain a `p` pointer (index) and `limit`; never read/write past `limit`. Use `uncheckedInc`/`dec` inside `{.push checks: off.}` regions.
- Avoid `seq` reallocation in writers by reserving capacity (exponential growth, like cbor-x-js buffer writers).

## Zero-Copy Reads (inspired by QCBOR)
- Return slices for byte/text strings referencing the input buffer; caller controls lifetime.
- Provide `copyText`/`copyBytes` helpers when owning data is needed.
- Indefinite-length strings: expose as an iterator of chunks; optional join helper that allocates.
- Map/array skipping: `skipItem(r)` advances past the current item (and nested items) without building structures.

## Streaming Reader/Writer
- Reader maintains a container stack with remaining item counts (or `indefinite = true`).
- `next(r, item)` yields items in document order: start-array/map, scalars, end markers (for indefinite only).
- Writer supports both known-length and indefinite containers; `endContainer` validates nesting.
- Backpatch utility for known-length containers when the size is known post-encode; or prefer pre-counting for canonical mode.

## Deterministic/Canonical Encoding (RFC 8949)
- Deterministic guarantees: smallest-length integer/float encodings; no indefinite-length strings/containers; map keys sorted by bytewise lexicographic order of their canonical encodings; preferred NaN representations.
- Canonical: shortest length for strings/byte strings where representable; smallest float that round-trips, else double.
- Key sorting: pre-encode keys to scratch buffers; sort by bytewise order; emit pairs. Offer `withScratch(w, buf)` to avoid heap temps.

## Derivation & Templates (msgpack4nim-inspired)
- Use templates/macros to generate `encode`/`decode` at compile time for object types.
- Default mapping: Nim objects → CBOR maps with string keys (field names) or arrays (positional) via pragma.
- Enums → ints or strings via pragma. Variants → tagged unions (discriminator as key or CBOR tag).
- Pragmas: `{.cborKey: "name".}`, `{.cborOmitIfDefault.}`, `{.cborAsArray.}`, `{.cborEnumAsString.}`; hook templates `beforeEncode(T)`, `afterDecode(T)`.
- Patterns from deps/msgpack4nim: use `fieldPairs` for reflection; specializations for primitives via overloading/`when compiles`; compile-time dispatch, no RTTI.

## Error Model
- No-exception fast path: return codes with out-params; `CborError` enumerates parse/validation failures.
- Exception wrappers for ergonomic one-shot APIs.
- Strict mode rejects duplicate map keys and invalid UTF-8 in text strings; liberal may allow and signal.

## Text Validation
- Optional UTF-8 validation (strict requires it). Fast ASCII scan; fallback to `unicode` validation.
- No allocation on success; return slice to original buffer.

## Floating-Point Strategy
- Decode: accept half/float/double; normalize to target type or `float64`.
- Encode: in deterministic mode choose smallest encoding that round-trips; canonicalize NaN payloads per RFC 8949.

## Indefinite-Length Items
- Reader: chunk iterator for strings and byte strings.
- Writer: supported but disabled in deterministic mode; emits `break` and validates nesting.

## Security & Limits
- Bounded recursion: `maxNesting` (default ~32) and `maxItemLen`.
- Resource caps: `maxTotalLen` to bound total processed input.
- Duplicate keys policy: strict rejects; liberal keeps first or last.

## Performance Plan
- Microbenchmarks: per-type encode/decode and mixed documents.
- Realistic workloads: streaming ND-CBOR logs; macro-derived object graphs.
- Adopt QCBOR patterns (zero-copy slices, bounded stacks, pull parser) and cbor-x-js patterns (pre-sized buffers, fast small-int paths, minimal branching).
- Nim-specific: disable bounds checks in hot paths; minimize ARC/ORC traffic; pre-size capacities; prefer stack temporaries.

## Interoperability & Compliance
- RFC 8949 baseline with profiles: Strict, LiberalDecode, Deterministic, Canonical.
- Tags: implement core numeric/time/bignum tags; extension registry `registerTag(tag, decodeProc)`.

## Project Layout
- `src/cborious.nim`: public API re-exports.
- `src/cbor/reader.nim`, `src/cbor/writer.nim`: core streaming codecs.
- `src/cbor/derive.nim`: macros/templates for compile-time deriving.
- `src/cbor/types.nim`: item structs, options, error types.
- `tests/`: RFC examples, golden vectors, round-trip, streaming, canonical sorting tests.
- `docs/rfc8949.md`: spec reference for cross-checking MUST/SHOULD.

## Implementation Roadmap
1) Core types and options; fast-path scalars; basic writer/reader.
2) Arrays/maps known-length; zero-copy slices; skipping; error model.
3) Indefinite-length containers and chunked strings; break handling.
4) Deterministic/canonical encoding; key sorting with scratch buffers.
5) Derivation macros/templates patterned on msgpack4nim; attributes.
6) Tags (bignum, time, decimal fraction); extension registry.
7) Text validation and liberal/strict decode profiles.
8) Benchmarks and tuning; property tests with golden vectors.

## References & Prior Art
- deps/msgpack4nim: compile-time deriving via templates/macros; specialization patterns for primitives and containers.
- deps/QCBOR: zero-copy pull parser, bounded stacks, deterministic guidelines and compliance focus.
- deps/cbor-x-js: high-performance buffer management, fast small-int and string paths, minimal branching.
- RFC 8949 (docs/rfc8949.md): definitive specification for CBOR format and canonical/deterministic requirements.

---
This architecture combines QCBOR’s tight C-level performance model, cbor-x-js’s pragmatic buffer strategies, and msgpack4nim’s Nim-centric compile-time deriving to deliver a fast, ergonomic, and standards-compliant CBOR for Nim.
