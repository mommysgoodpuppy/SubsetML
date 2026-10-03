# Portable bytes and Unicode text

Status: source byte readers, strict UTF-8/UTF-16 codecs, native-string conversion and a
source-built byte index are implemented (2026-10-02). Both compiler lexers use the index.
The opaque-string adapters require one extraction operation; construction uses source literals
and concatenation. This is an implemented initial boundary, not a frozen ABI. JavaScript's
representation and frontend-v3's editor offset conventions remain target details.

The [Basis portability rule](basis.md#portability-rule) applies: anything reasonably expressible
in SubsetML gets a shared source implementation rather than becoming a required host service.
Optional acceleration must preserve the same contract and a portable source path.

## Data before target representations

Use ordinary byte sequences as the common interchange representation. The baseline can use
`char list`: the language's `char` has codes 0–255, and `SubsetChar.toCode/fromCode` already
convert those values using source tables. A binary payload is valid bytes regardless of whether
it is valid text. A host must not decode it implicitly on read or encode it implicitly on write.

Unicode scalar values are separate library values, with numeric codes represented by the
language's current `real` type. These bounded codes are exactly representable. Valid scalar
codes exclude surrogates; codecs validate integral inputs and ranges. They must not reinterpret
the language's byte `char` as a Unicode scalar. Because the language lacks opaque module types,
constructor wrappers alone cannot enforce validity: operations accepting externally constructed
values must validate them, or expose a clearly specified already-validated internal path.

| Layer | Representation/contract | Additional target primitives |
|---|---|---|
| Bytes | Ordinary byte-character sequences; every byte value is allowed | none |
| Unicode scalars | Checked numeric codes, distinct from byte characters | none |
| UTF-8 | Encode/decode between bytes and scalars | none |
| UTF-16LE / UTF-16BE | Encode/decode between bytes and scalars, explicit byte order | none |
| Source reader | Byte storage plus explicit offset/cursor policy | none |
| Existing native `string` | Bridge to/from byte values | one extraction operation for opaque native strings |
| File/console I/O | Read/write byte sequences | host operations, independent of codecs |

`SubsetBytes`, `SubsetUnicode`, `SubsetUtf8` and `SubsetUtf16` implement this source layer.
Their [APIs and error-offset contracts](basis.md#strict-unicode-codecs) are documented separately. UTF-8 and UTF-16 are sufficient
initial targets, not a promise that all encodings, Unicode normalization, grapheme segmentation
or Unicode classification data are implemented. Those can be separate source libraries.

## One native-string extraction operation

`SubsetTextHost.codes string` returns raw numeric character codes in storage order. The native
SML adapter uses `String.explode` and `Char.ord`; the Workman adapter uses JS string length and
`charCodeAt`. The shared `SubsetString.fromNative` validates each code as an integral byte and
returns `Err (NonByte offset)` at the first invalid element. JS UTF-16 units above 255,
including surrogate units, are rejected. No implicit Unicode encoding takes place.

`SubsetString.toNative bytes` needs no host operation: a source table maps all 256 byte
characters to one-byte string literals, then joins them with ordinary `^`. It validates foreign
characters and reports the same indexed NonByte error. Pairwise concatenation avoids repeated
copying of a growing prefix; with flat strings, total copying is O(n log n). Table lookup is
bounded by 256 comparisons per character. Embedded NULs and high bytes round-trip exactly.
Allocation exhaustion remains a runtime resource failure rather than a fabricated Result error.

The adapters live in `lib/subset_text_host.sml` and `lib/subset_text_host.wm`. The checker uses
an ordinary source stub, `src/subset_text_host.sml`, so imports need no special translation rule.
`make wm` stages the WM adapter after ordinary translation. All validation, construction,
indexing and codecs are generated from shared SubsetML source.

A backend representing strings as ordinary byte sequences can implement extraction in source
or as an identity. One is the practical extra operation for the current opaque-string targets,
not a universal lower bound. Packed storage and native indexing/slicing are optional accelerations.

## Source algorithms above the bridge

Length, equality, comparison, indexing, slicing, concatenation, search, splitting, escaping and
builders can operate on byte sequences. The language still retains its prescribed `string`
semantics and fixed operators; library representation choices do not change the language spec.

UTF codecs likewise need no host Unicode service. Byte/scalar fields can be assembled and
split with bounded source arithmetic. Division by powers of two, integral validation and
remainder can use source algorithms on these small exact ranges; numeric floor, bitwise
operations and integer conversion need not become codec intrinsics. The implemented codecs use fixed binary weights to split values without host floor or
bitwise operations; cross-target boundary/reference tests cover these algorithms.

Decoders should be strict by default: malformed, truncated and out-of-range input returns a
typed error with an offset in the input's stated unit. Replacement-character recovery, if
provided, must be a separate explicit policy. UTF-16 byte decoders validate byte pairs and
surrogate pairing. Endianness is selected by the API; BOM detection or consumption is an
explicit higher-level policy rather than implicit host behavior.

## Efficient readers without extra requirements

Convert a native string once, not on every peek. A sequential lexer can advance an immutable
list cursor while retaining its original bytes and absolute offsets. Keep offset information
separate from decoded scalar values so spelling and spans remain available.

Random access into a list is linear. Where a parser/editor needs repeated random access or
slicing, ordinary source can build a persistent balanced tree or chunked representation with
cached lengths. This takes work and allocation, but does not require arrays or native string
intrinsics. A packed/indexed target implementation can be added behind the same public
contract later if measurements justify it.

`SubsetSource` builds a balanced immutable byte tree with cached lengths in O(n) time.
Lookup is O(log n); slicing visits the selected bytes and boundary paths. Its factories validate
foreign bytes or convert a native string once. Both compiler lexers now use this index for input
lookahead and spans, with byte offsets and typed rejection of non-byte source text. The internal
`CompilerText` compatibility module asserts established bounds when adapting these Results to
existing lexer code. The parser now uses checked byte conversion for identifier/label classification and source
concatenation for qualified-name diagnostics. The remaining compiler text helpers now also use this source layer. The document renderer now uses the source index for original
source positions, plus shared trimming, field splitting and checked repetition for layout. The SML source and AST debug printers use source byte escaping and concatenation. The Workman
printer also uses source character construction, name conversion and hexadecimal escaping,
without native slicing/indexing or numeric div/mod.

## Frontend-v3 and offset profiles

Frontend-v3 caches JS string length and uses `charCodeAt` and `slice`; it records UTF-16 offsets
for its structural editor and counts Unicode scalars for character literals. Those are valid
requirements for that consumer, not a common storage requirement.

The source reader should state its offset units. The current SubsetML compiler uses byte
positions; a Unicode reader may additionally track scalar positions and UTF-16-unit positions
for an editor. Scalar-to-UTF-16 position accounting is source arithmetic: supplementary scalars
advance two units, others one. A mapping between byte offsets and editor offsets can be recorded
while decoding. UTF-16 profiles must also specify behavior for offsets inside a surrogate pair
and for damaged/lone-surrogate editor buffers; strict scalar text cannot preserve those as
valid Unicode scalars. A raw UTF-16-unit/byte view can retain damage without silently repairing it.

Consequently, porting v3 should preserve its explicit editor contract through a source adapter,
not require every SubsetML string to use JS's UTF-16 representation. Its probing beyond EOF
must become an explicit optional/error result instead of depending on host NaN behavior.

## Next implementation steps

1. **Done:** source byte readers, strict UTF-8/UTF-16 codecs and cross-target reference tests.
2. **Done:** one extraction adapter, checked source string conversion and a balanced source index.
3. **Done:** convert each lexer input once and remove its indexed bootstrap String dependencies.
4. Migrate remaining compiler text operations and check the generated compiler graph.
5. Add editor offset adapters separately; optimize storage after measuring actual workloads.

The compiler types, unifier, elaborator, reverse parser, normalization and translation now
use source text operations. CLI text helpers use the byte layer; file/process access is
provided by the six-operation SubsetIo/SubsetProcess CLI profile; source module loading adds
filesystem canonicalization as a separate host operation. Exact count formatting is provided by
`SubsetNatural`; arbitrary floating-point formatting is a separate contract.
