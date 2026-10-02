# SubsetML Basis

This document specifies the library separately from the [SubsetML language](spec.md).
The SubsetML Basis is a custom library, inspired by the SML Basis Library rather than a
subset or compatibility implementation of it. The library is designed for SubsetML's language
features and for sharing ordinary source with Workman.

Its design should favor `Result` for fallible operations, convenient and consistent argument
order, and ordinary SubsetML implementations over host-specific library code. A small primitive
layer will supply operations that require target representation or I/O access. Workman's current
separate Basis should eventually be replaced by this shared library.

The first custom collection and character APIs are implemented below. Names and signatures are an initial
library version; further modules and the primitive interface remain to be designed. This decision changes the library contract, not SML's language semantics:
MLton builds must supply the custom Basis rather than assume its stock SML Basis has the same
names and APIs.

## Portability rule

**Anything reasonably expressible in SubsetML should have a portable source implementation
and should not be required from the host.** This is the default for new Basis APIs and for
migration of existing host dependencies. The shared source is the canonical implementation
and generates Workman through the ordinary translator.

"Within reason" means an implementation with practical behavior, manageable complexity and
explicit contracts. It does not justify requiring a host function simply because that function
already exists there. It does allow keeping genuinely external I/O and access to opaque target
representations in thin adapters. Ordinary language/runtime support remains the backend's
responsibility. Resource/performance limits must be documented rather than hidden in semantics.

An optional accelerated implementation may satisfy the same observable contract, including
errors, callback order and encoding behavior. It must not become necessary for correctness or
portability; measure workloads before expanding required primitives for speed. Before adding
a required kernel call, record why a reasonable source implementation or source data
representation is insufficient and review that boundary explicitly.

## Implemented custom APIs

The custom modules use a `Subset` prefix to distinguish them from the bootstrap host library
and the earlier `Sml` ports. They are ordinary program modules, not checker-provided magic.
Load them before a program when checking or building SML. The translator generates their
Workman implementations and normal imports; there is no independently maintained WM version.

Multi-argument operations use **data-first tuple arguments**, for example
`SubsetList.map (xs, f)` and `SubsetList.foldLeft (xs, initial, f)`. Unary operations take their
value directly. Fold callbacks take `(element, accumulator)`; paired-list callbacks take
`(leftElement, rightElement)`. These conventions deliberately differ from the SML Basis.

### Result and optional values

`SubsetResult` defines `datatype ('a, 'e) result = Ok of 'a | Err of 'e`. Errors are typed,
ordinary values chosen by each operation or its caller. There is no unsafe unwrap.

| Operation | Contract |
|---|---|
| `SubsetResult.map (result, f)` | Transform Ok; preserve Err without calling f. |
| `SubsetResult.mapError (result, f)` | Transform Err; preserve Ok without calling f. |
| `SubsetResult.andThen (result, f)` | Call a Result-producing f only for Ok. |
| `SubsetResult.getOr (result, fallback)` | Return the successful value or the supplied fallback. |
| `SubsetResult.isOk result` | Test the constructor. |
| `SubsetResult.toOption result` | Ok becomes SOME; Err becomes NONE, explicitly discarding its error. |
| `SubsetOption.getOr (option, fallback)` | Return the present value or fallback. |
| `SubsetOption.isSome option` | Test presence. |
| `SubsetOption.map (option, f)` | Transform SOME; leave NONE alone. |
| `SubsetOption.andThen (option, f)` | Call an option-producing f only for SOME. |
| `SubsetOption.filter (option, predicate)` | Keep a present value satisfying the predicate; otherwise NONE. |
| `SubsetOption.toResult (option, error)` | SOME becomes Ok; NONE becomes Err with the caller's error. |

Option uses the existing `option` datatype (`NONE`/`SOME`, generated as `None`/`Some`), rather
than a second representation. Tuple arguments are evaluated normally by SML: fallback values
and supplied errors are eager, not lazily invoked callbacks.

### Error procedures

A **procedure** is an ordinary function that returns a Result. It starts with a Result value,
passes that value through named transformations, and returns a Result for its caller to handle.
This is a coding pattern, not a language construct. It avoids deeply nested `andThen` callbacks
without exceptions, early-return syntax or new host operations.

The runnable [errordemo.sml](../errordemo.sml) defines two local adapters:

```sml
val via = fn transform => fn wrapped =>
  SubsetResult.andThen (wrapped, transform)

val viaError = fn inject => fn transform => fn wrapped =>
  SubsetResult.andThen (wrapped, fn value =>
    SubsetResult.mapError (transform value, inject))
```

These are ordinary curried functions. They are local prototypes in the demo, not currently
exports of `SubsetResult`; the core data-first `andThen` and `mapError` APIs remain unchanged.

- `via transform` adapts a function from an unwrapped value to a Result into a function from
  one Result to another. It calls `transform` only on success and preserves an existing error.
- `viaError inject transform` also maps the transformation's own error into the procedure's
  shared error type. It preserves an incoming error without calling either `transform` or
  `inject`. The error mapper can be an ordinary datatype constructor.

Each stage can change the successful value's type. All stages share one application error
datatype, while the underlying operations can retain their own error types. In the demo,
`InputFailure`, `ParseFailure` and `ValidationFailure` identify the failing stage:

```sml
val compileInput = fn input =>
  let
    val read = viaError InputFailure readInput
    val parse = viaError ParseFailure decode
    val compile = via requirePositive

    val loaded = read (SubsetResult.Ok input)
    val parsed = parse loaded
  in
    compile parsed
  end
```

The sequential `val` bindings keep the procedure flat. After failure, subsequent adapters
still run, but only propagate the Err; their underlying transformations do not run. This
lets a caller perform one exhaustive `case` at a reporting or recovery boundary. Within a
procedure, use an explicit `case` or `andThen` when branching on a successful value makes the
control flow clearer. Carry a tuple or record as the successful value when later stages need
information from earlier stages.

Ordinary argument evaluation remains eager. Calling an effectful operation before passing
its result to an adapter cannot be undone or skipped. Put work that must stop after failure
inside the transformation. Similarly, placing already computed Results in a tuple does not
sequence or short-circuit the operations that produced them.

Expected input, decoding and validation failures should remain typed errors until a reporting
boundary converts them to text. A binding such as `val Ok value = operation input` is instead
a partial assertion: Err causes a pattern-match failure. This procedure pattern does not
make such assertions safe or remove their exhaustiveness warnings. It also does not change
the stack requirements of recursive AST algorithms.

#### Differences from Workman ergonomics

The pattern follows wm-mini's [carrier-oriented procedure design](../../wm-mini/docs/carriers.md).
Its Result adapters have the same propagation behavior, but SubsetML uses ordinary SML syntax:

| Workman facility | SubsetML form or scope |
|---|---|
| `Monad.via Result transform` | The demo's Result-specific `via transform`; no carrier record is required. |
| `Monad.viaError Result inject transform` | The demo's `viaError inject transform`. |
| `head :> read :> parse :> compile` | Sequential `val` bindings and ordinary function application. SubsetML has no pipeline operator. |
| `Result\|a, b\|` carrier tuple lifting | No corresponding syntax. Use ordinary source helpers built from `andThen` and `map`, keeping deferred work inside callbacks when it must short-circuit. |
| Carrier-generic `Monad` operations | The demo specializes to Result. A generic carrier abstraction is not needed for this pattern. |
| `Task` and safe foreign-call error wrapping | Outside this demo and the current custom Result API. Host failures enter through the explicit adapters, such as `SubsetIo`; the pattern supplies no asynchronous runtime or exception catching. |

Workman's pipeline and tuple-lift syntax are conveniences around carrier composition;
`procedure`, `via` and `viaError` are not exception or early-return keywords there either.
The shared portable part is the functions, typed errors and propagation discipline. Normal
translation generates the demo's Workman implementation without replacing it with Workman's
separate Result library or requiring these syntax conveniences.

To check and run the example with MLton:

```sh
bin/subsetml check src/subset_result.sml errordemo.sml
mlton -output /tmp/errordemo errordemo.mlb
/tmp/errordemo
```

The demo prints `error procedure demo: ok` after checking success, each stage's error and
skipping an effectful transformation after an earlier failure. It also checks and runs after
translation to Workman.

### Lists

| Operation | Contract |
|---|---|
| `isEmpty xs`, `reverse xs`, `length xs` | Empty test, reversed list and real-valued element count. |
| `reverseAppend (xs, ys)`, `append (xs, ys)` | Reverse xs onto ys, or concatenate xs followed by ys. |
| `concat lists` | Flatten while retaining list and element order. |
| `foldLeft (xs, initial, f)` | Invoke f from left to right. |
| `foldRight (xs, initial, f)` | Invoke f from right to left. |
| `forEach (xs, f)` | Invoke a unit-returning f from left to right. |
| `map (xs, f)` | Transform elements from left to right, preserving output order. |
| `filterMap (xs, f)` | Keep the SOME results of f, in input order. |
| `filter (xs, predicate)`, `partition (xs, predicate)` | Preserve order within retained/rejected lists; predicates run left to right. |
| `find (xs, predicate)`, `exists (xs, predicate)`, `all (xs, predicate)` | Stop at the first decisive predicate result. Empty find is NONE, exists is false, all is true. |
| `dropWhile (xs, predicate)` | Drop a prefix; invoke the predicate left to right, stopping at the first false result. |
| `repeat (value, count)` | Ok list of count copies, or Err InvalidCount. |
| `splitAt (xs, index)` | Ok (prefix, suffix), with exactly index elements in prefix. |
| `at (xs, index)` | Ok element at the zero-based index. |
| `take (xs, count)`, `drop (xs, count)` | Ok prefix or suffix; never silently truncate. |
| `tabulate (count, f)` | Ok generated list; invoke f at real indices 0 through count−1, left to right. |
| `head xs`, `tail xs`, `last xs` | Return Ok on a nonempty list; Err EmptyList on an empty list. |
| `traverse (xs, f)` | Invoke a Result-producing f left to right; stop at its first Err, preserving that error. Successful output order matches the input. |

These operations are in `SubsetList`. Its error type is `datatype error = EmptyList | InvalidCount | InvalidIndex | OutOfBounds`.
`repeat` and `tabulate` accept finite integral counts from zero through 2^53−1, including negative zero.
It checks the count with bounded source binary arithmetic before allocating any list cells;
negative, fractional, non-finite and larger counts return InvalidCount. The bound keeps
countdown exact under the current binary64 numeric profile. Allocation exhaustion remains a
runtime failure, not InvalidCount.
Invalid indices/counts for `splitAt`, `at`, `take`, and `drop` return `InvalidIndex`;
valid integral positions beyond the list return `OutOfBounds`. Splitting/taking/dropping
at the list's length succeeds; accessing an element there returns `OutOfBounds`.
`tabulate` validates its count before invoking any callback. These operations are source-only.

An unsuccessful traverse returns no partial output list. Callback effects already performed
remain; the library does not roll them back or catch exceptions from callbacks.

### Exact natural numbers

`SubsetNatural` operates on real-valued exact nonnegative integers from zero through
2^53−1 in the current binary64 profile. `isValid value` tests this domain; negative zero
is accepted. `divide (value, base)` returns `Ok (quotient, remainder)` with integer quotient
and 0 ≤ remainder < base. Invalid values return `InvalidNatural`; invalid or zero divisors
return `InvalidDivisor`. The value is checked before the divisor.

`toString value` returns `Ok` ordinary unsigned decimal text, including `"0"` for either
signed zero; invalid input returns `InvalidNatural`. It formats integers only. Neither
operation needs host floor, division/modulo helpers or number formatting: division uses
53 descending binary weights, and formatting repeatedly splits by ten. `split` is an
internal unchecked helper for operands already known to satisfy the same domain.

The compiler uses this module for type-variable names, counts in diagnostics and its
persistent integer-map arithmetic. Tuple labels use a decimal character counter directly.

### Whole-file byte I/O and process profile

`SubsetIo` provides checked whole-file I/O. File contents and standard-output/error payloads
are `char list` bytes; no text decoding, BOM handling, newline conversion or newline insertion
occurs. Use the source UTF codecs explicitly for text. Its error type is
`HostError of string | NonByte of real | InvalidPath`.

| Operation | Contract |
|---|---|
| `readFile path` | Ok complete file bytes, or an error. |
| `writeFile (bytes, path)` | Create/truncate and write the complete payload; return Ok unit on success. Parent directories must already exist. |
| `writeStdout bytes`, `writeStderr bytes` | Write exactly the supplied bytes; return Ok unit on success. |
| `errorText error` | Diagnostic byte string; host messages are target-dependent. |

Paths are native byte strings interpreted by the adapter's filesystem convention. Source
validation rejects non-byte paths and embedded NUL, and checks write payloads before opening
files. `NonByte offset` identifies a foreign byte value outside 0–255; invalid NUL paths return
`InvalidPath`. Operational failures return `HostError`; partial writes or truncation may have
already happened, so this is not a transactional API. Adapters drain short writes; they report
zero-progress writes as errors. These operations are synchronous in the current CLI profile.

`SubsetProcess.arguments ()` returns `Ok` a list of validated argument byte strings, excluding
the executable name, or a `SubsetIo.error`. It does not decode argument text.
`SubsetProcess.exit success` terminates with success/failure (0/1 in the current adapters) and
never returns. Arbitrary status codes and stream handles are outside this initial profile.

The native adapter uses binary file I/O and raw POSIX output. The Workman adapter uses a
Latin-1 carrier string only inside the FFI boundary, with Node binary file/output calls. It
encodes Deno's Unicode argument and error-message text as UTF-8 bytes; the native adapter
preserves OS byte strings. Neither adapter silently decodes file contents. These target
marshalling conventions are not SubsetML's language string representation requirements.

The six operations live in `SubsetHost`; the public `SubsetIo` and `SubsetProcess` wrappers
are source code. Together with native-string extraction, the current compiler needs seven
explicit host entry points beyond language support. Embeddings can omit the CLI profile.

### Paired lists

`SubsetListPair` treats unequal lengths as an error rather than silently discarding elements.

| Operation | Contract |
|---|---|
| `zip (left, right)` | Ok pairs in order, or Err UnequalLengths. Two empty lists succeed. |
| `unzip pairs` | Return the two component lists in order. |
| `map (left, right, f)` | Validate lengths, then map f over pairs; return Ok output or Err UnequalLengths. |
| `traverse (left, right, f)` | Validate lengths, then invoke a Result-producing f left to right. |

The ordinary paired-list error is `datatype error = UnequalLengths`. Traversal distinguishes
structural failure from callback failure with
`datatype 'e traversalError = LengthMismatch | CallbackError of 'e`.
Length mismatch invokes **no callbacks**. After validation, the first callback Err stops
traversal and is wrapped in CallbackError without losing its value. Validation currently
materializes the zipped pairs, using linear extra space before mapping or traversal.

### Ordering and ASCII characters

`SubsetOrder` defines `datatype order = Less | Equal | Greater` and `reverse order`.
These are ordinary constructors, translated with the module; they do not need Workman's
bootstrap `LESS`/`EQUAL`/`GREATER` definitions.

`SubsetOrder.compareReal (left, right)` returns `Ok Less`, `Ok Equal`, or `Ok Greater`,
or `Err SubsetOrder.Unordered` if either operand is NaN. It uses the language's real comparison
operators only, with no host `Real.compare` or equality binding. Signed zeros compare Equal;
infinities use their ordinary numeric order. The parser uses this source comparator for its
finite precedence constants, so it no longer depends on host ordering constructors.

`SubsetChar` implements `isLower`, `isUpper`, `isDigit`, `isGraph`, `isPrint`, `isCntrl`,
`isAscii`, `isAlpha`, `isAlphaNum`, `isHexDigit`, `isSpace`, `isPunct`, `toLower`, and `toUpper`.
Classification is explicitly ASCII, independent of locale. Control characters are ASCII
0–31 and 127. Case conversion changes ASCII letters only and preserves other characters.
The implementation uses literal tables and character equality, including a 26-entry case
mapping. `contains (characters, character)` tests membership in a character list
(data first), short-circuiting on a match; an empty list returns false. It needs neither character ordering nor `ord`/`chr` nor string access. Table scans
are bounded but cost more comparisons than direct code/range tests.

`compareAscii (left, right)` returns `Ok SubsetOrder.Less`, `Equal`, or `Greater`, in ASCII
code order, or `Err SubsetChar.NonAscii` if either operand is outside ASCII. General 8-bit character
ordering remains pending; checked code conversions are implemented below, and the language's character range
is already 0–255. Unicode host values need explicit boundary handling. Workman's current `<`
operator does not accept `Char`, so ordinary SML character range tests are not portable to
that target today. The source tables avoid that dependency.

The compiler uses `SubsetChar` for classification, ASCII case conversion and membership in its
literal symbol/punctuation lists. It no longer imports the old `SmlChar` module, which remains
only as a compatibility port for regression tests. String membership can use the checked byte conversion API.

### Byte character codes

`SubsetChar.toCode character` returns `Ok code` for codes 0–255, or `Err NonByteCharacter`
for a foreign target character outside that domain. `fromCode code` returns `Ok character`,
or `Err InvalidCode` for negative, fractional, non-finite or greater-than-255 values. Negative
zero is accepted as code zero. Both operations scan a fixed source table, bounded by 256
entries, and need neither `ord`/`chr` nor numeric floor/integer conversion primitives.

The compiler's escape decoders now handle `fromCode` failures through their ordinary lexical
error results. Fixed control escapes use literals. Numeric digit accumulation and Workman
printing assert that their input characters belong to the language's byte domain; the checked
native-string boundary validates that domain before supplying lexer text. No unchecked unwrap
has been added to the custom Basis API.

Ordering operators `<`, `>`, `<=`, and `>=` accept only `real` operands in SubsetML.
Text ordering uses explicit source functions. `SubsetBytes.compare (left, right)` and
`SubsetString.compare (left, right)` return `Ok SubsetOrder.Less`, `Equal`, or `Greater`
in unsigned byte lexicographic order; a proper prefix sorts first. This is byte ordering,
with no Unicode normalization, locale or collation. Both complete operands are validated
before comparison, left first; foreign non-byte data returns `Err (NonByte offset)` from
the respective module, even after a decisive prefix. The offset is within the invalid operand.
Time and temporary storage are O(n + m); no additional host primitive is required.

### Byte sequences and readers

`SubsetBytes` uses `char list` storage. `validate bytes` checks the byte domain and returns
`Ok bytes` or `Err (NonByte offset)` for a foreign non-byte character. `length bytes` counts
elements. These counts are real-valued, as required by the current language.

| Operation | Contract |
|---|---|
| `trim (bytes, predicate)` | Remove matching bytes at both ends; preserve the middle. |
| `fields (bytes, delimiter)` | Split on matching bytes, preserving empty fields, including at either end. Empty input gives one empty field. |
| `reader bytes` | Validate once, then return an immutable reader positioned at byte offset zero. |
| `position reader`, `peek reader` | Absolute byte offset; optional current byte without advancing. |
| `next reader` | SOME (byte, advancedReader), or NONE at EOF. The original reader remains usable. |
| `splitAt (bytes, index)` | Ok (prefix, suffix), accepting zero through length inclusive. |
| `at (bytes, index)` | Ok byte, or Err OutOfBounds at the end of the sequence. |
| `slice (bytes, start, count)` | Exact slice; zero-length slices at EOF succeed. |

Indexed operations reject negative, fractional, non-finite and beyond-length positions/counts
with `InvalidIndex`; they never silently truncate. They operate on byte sequences already in
the language domain; use `validate` when receiving foreign data. `fields` invokes the delimiter once per byte, left to right. `trim` first scans the left
prefix, then the remaining right suffix backwards; each scan stops on its first non-match.
These operations assume byte-domain input, like the indexed operations. List-backed indexing/slicing
is linear, and sequential `peek`/`next` is constant time after reader creation. Reader
constructors are visible because SubsetML has no opaque signatures; consumers should use the
reader factory rather than forge states.

### Native strings and indexed sources

`SubsetString.fromNative string` returns `Ok bytes`, or `Err (SubsetString.NonByte offset)`
at the first native element outside the byte domain. It calls the one extraction operation
`SubsetTextHost.codes`, then validates in shared source. `toNative bytes` returns an exact
native string or the same indexed error for a foreign character. Its complete literal table
and pairwise concatenation need no construction primitive. Empty input, NULs and all high bytes
are preserved. Neither operation encodes or decodes Unicode. `concat strings` joins in order with pairwise
concatenation; `concatWith (strings, separator)` inserts separators between adjacent strings,
including empty strings. Empty input returns the empty string. These operations assume language
strings, like `^`, and do not inspect or validate foreign text. They need no additional host call.
Allocation exhaustion remains a
runtime failure; these Results describe invalid data, not available memory.

`SubsetSource.fromBytes bytes` validates and builds an immutable balanced byte index;
`fromNative string` performs checked conversion once, then builds the same index. The former
returns `SubsetBytes` errors, the latter `SubsetString` errors. `length source` is constant time;
`at (source, index)` returns a byte in O(log n). `slice (source, start, count)` returns bytes,
visiting the selected range and boundary paths. Invalid, fractional, non-finite or out-of-range
indices/counts return `SubsetBytes.InvalidIndex`; zero-length slices at EOF succeed. Build time
is O(n), with O(n) nodes. Use the factories rather than forging visible tree constructors;
`build`, `join` and `boundary` are internal implementation interfaces.

Both compiler lexers use this index and report non-byte source text as a lexical error at its
byte-boundary offset. `CompilerText` is a transitional compiler helper, not a public Basis API;
its refutable bindings assert established byte-domain and lexical/layout bounds.
The document renderer converts source input once, uses the source index for positions and
uses shared trimming, splitting, concatenation and repetition for output.
`tests/doc-portable.sh` checks exact layout, comment placement and helper contracts with
original SML, round-tripped SML and generated Workman.

### SML literal escaping

`SubsetSmlEscape.escapeByte byte`, `escapeBytes bytes` and `escapeString string` return
Result containing **literal contents**, without surrounding quotes or the character-literal
prefix. Callers supply those delimiters. Byte inputs need no host calls; native string input
uses the existing checked extraction boundary. Empty sequences/strings return an empty string.

A complete source table supplies printable ASCII, escaped quote/backslash, named control
escapes, caret escapes for the other ASCII controls and three-digit decimal escapes for
127–255. Non-ASCII bytes are always escaped; Unicode encoding and classification are absent.
Errors are `NonByte offset`: zero for an invalid single byte, the first invalid element's index
for sequences or native strings. No partial output is returned. Table lookup is bounded by
256 comparisons per byte; fragments are joined with source balanced concatenation.

`tests/sml-printer.sh` compares every byte's spelling and the combined byte string against an
independent MLton `Char.toString`/`String.toString` oracle, then decodes the emitted literals
with the shared lexer. Original SML, round-tripped SML and Workman execute the same cases.
It also checks printer precedence, nested conditionals, comments and foreign-byte rejection.
The SML source printer and AST debug printer both use this module through internal checked
compatibility helpers; those helpers assert the compiler's established byte-domain invariant.

### Strict Unicode codecs

`SubsetUnicode.isScalar code` checks integral Unicode scalar codes, excluding surrogates.
The codecs operate on numeric scalar lists and byte-character lists; no host Unicode, floor,
integer-conversion or bitwise functions are required. Internal bounded binary arithmetic
preserves fractional residues during validation. Scalars and byte characters remain distinct.

| Operation | Successful value |
|---|---|
| `SubsetUtf8.encode scalars` | UTF-8 bytes |
| `SubsetUtf8.decode bytes` | Unicode scalar codes |
| `SubsetUtf16.encode (scalars, endian)` | UTF-16 bytes, in LittleEndian or BigEndian order |
| `SubsetUtf16.decode (bytes, endian)` | Unicode scalar codes |

All four return Result. Empty input succeeds. BOMs are ordinary U+FEFF values, with no automatic
insertion, stripping or byte-order detection. Noncharacters are accepted scalar values. These
rules follow the [Unicode encoding definitions](https://www.unicode.org/versions/Unicode16.0.0/core-spec/chapter-3/).

Errors are `SubsetUnicode.Error (reason, offset)`. Encoder offsets count scalar-list elements;
decoder offsets count input bytes. Since offsets/scalars use `real`, destructure them and use
real comparison rather than SML structural equality on Result values containing them.
Validation returns the first detected error with no partial
output. Invalid leaders/continuations identify the offending byte. Truncation identifies the
EOF offset. Overlong, surrogate and above-maximum UTF-8 sequences identify their leading-byte
offset after the complete sequence is read. UTF-16 odd-length errors identify the final
unpaired byte; unexpected surrogate units identify their own first byte. Missing units after
a high surrogate identify EOF. Invalid scalar inputs identify their scalar index.

The reason constructors are `InvalidScalar`, `InvalidByte`, `InvalidLeadingByte`,
`InvalidContinuation`, `Truncated`, `Overlong`, `Surrogate`, `OutOfRange`, `OddLength` and
`UnpairedSurrogate`. Invalid UTF-8 leaders C0/C1 report InvalidLeadingByte. Encoders check inputs
without relying on wrapper-constructor validity. There is no replacement-character recovery.

`make text-basis-check` verifies portable readers, exact failure offsets, and codecs against
Python-generated independent strict UTF-8/UTF-16 vectors. The same fixtures execute with
original MLton source, round-tripped library source and generated Workman. Deterministic random
scalars, arbitrary bytes, boundary values and truncated encodings supplement explicit error
cases. Helper functions such as `split`, `encodeOne`, `decodeOne` and `readUnit` are internal
implementation interfaces; the stable entry points are the operations documented above.

## Dependencies and primitive boundary

The dependency inventory is [basis-dependencies.json](basis-dependencies.json). Each implemented
custom module declares its source dependencies and explicit primitive calls. The current graph is:

| Module | Source dependencies | Explicit host primitive calls |
|---|---|---|
| `SubsetResult` | none | none |
| `SubsetOption` | SubsetResult | none |
| `SubsetList` | SubsetResult | none |
| `SubsetListPair` | SubsetResult, SubsetList | none |
| `SubsetOrder` | SubsetResult | none |
| `SubsetChar` | SubsetOrder, SubsetResult | none |
| `SubsetBytes` | SubsetChar, SubsetList, SubsetOrder, SubsetResult | none |
| `SubsetUnicode` | SubsetChar, SubsetList, SubsetResult | none |
| `SubsetUtf8` | SubsetChar, SubsetList, SubsetResult, SubsetUnicode | none |
| `SubsetUtf16` | SubsetChar, SubsetList, SubsetResult, SubsetUnicode | none |
| `SubsetString` | SubsetBytes, SubsetChar, SubsetList, SubsetResult | SubsetTextHost.codes |
| `SubsetNatural` | SubsetList, SubsetResult, SubsetString | none |
| `SubsetSource` | SubsetBytes, SubsetList, SubsetResult, SubsetString | none directly; extraction through SubsetString |
| `SubsetSmlEscape` | SubsetList, SubsetResult, SubsetString | none directly; native-string entry uses extraction through SubsetString |
| `SubsetIo` | SubsetList, SubsetResult, SubsetString | SubsetHost.readFile, writeFile, writeStdout, writeStderr |
| `SubsetProcess` | SubsetIo, SubsetList, SubsetResult | SubsetHost.arguments, exit |

This does not mean a backend needs no runtime. It needs ordinary language support for datatype
values, options, lists, tuples, booleans, unit, functions, pattern matching, recursion, character literals and character equality.
User callbacks may introduce their own dependencies; they are not hidden library primitives.

No final primitive ABI is assumed yet. Native string conversion, byte-list/tree indexing
and codec failure contracts are implemented above; streaming and broader resource contracts remain pending.
The older character port demonstrates candidate needs for string size/subscript and character
code conversion; it does not establish that all four must remain primitives in the final design.
For example, some algorithms could use character lists instead of indexed strings. Future
operations should first try existing custom source functions, then record any primitive they
actually require. Representation access, arithmetic and I/O are likely boundaries. A concrete candidate budget
and the compiler's current requirements are in [self-hosting-kernel.md](self-hosting-kernel.md).

The existing MLton and Workman print operations differ in newline behavior. A future shared
output API must define whether it writes supplied bytes or whole lines. The collection tests
compare complete callback trace tokens while ignoring empty lines caused by that bootstrap
output difference; this is not a claim of portable I/O semantics.

`make custom-basis-check` validates the source graph, translation and callbacks. It builds
both original and round-tripped modules with MLton and checks/runs the generated graph with
`wm` when installed. The tests cover empty lists, both length-mismatch directions, callback
order, short-circuiting, preserved callback errors and skipped callbacks on structural failure.
Character tests compare all 256 MLton character values and all 65,536 operand pairs in both
original and round-tripped source, including rejection of every non-ASCII comparison. Workman
executes all 256 byte literals against classification expectations and representative casing
and ordering/error cases. The same byte corpus checks code conversion in both directions;
invalid numeric codes and a foreign non-byte Workman character are also checked. A generated numeric-ordering fixture checks both operand orders for
NaN, signed zero and infinities in Workman and round-tripped MLton code. These checks are also part of `make test`. The module dependency inventory is audited against
parsed syntax, so introducing a qualified host call requires updating its declared dependencies.

## Current implementation and migration

`src/basis.sml` is still a table of bootstrap compatibility interfaces used by the checker.
`lib/num.sml` is the full-SML numeric adapter used by legacy tests. Neither defines the final custom
Basis API. The compiler now uses source algorithms and the two explicitly staged host adapters.

The bootstrap numeric adapters use real-valued sizes and indices because the language
currently omits `int`. `lib/num.sml` is full SML outside the portable sources: indexed arguments
must be finite integral reals within MLton's `int` range; invalid arguments raise `Domain`.
Numeric division and remainder currently share that range restriction. These exception-based
contracts and SML-shaped namespaces are temporary adapter behavior, not the custom Basis API.

The first portable modules live alongside the compiler sources:

| Module | Implemented functions |
|---|---|
| `SmlList` (`src/sml_list.sml`) | `null`, `revAppend`, `rev`, `foldl`, `foldr`, `concat`, `app`, `map`, `mapPartial`, `find`, `filter`, `partition`, `exists`, `all` |
| `SmlListPair` (`src/sml_list_pair.sml`) | `zip`, `unzip`, `map`, `app`, `all`, `exists` |
| `SmlOption` (`src/sml_option.sml`) | `getOpt`, `isSome`, `map`, `mapPartial`, `join`, `filter`, `compose`, `composePartial` |
| `SmlChar` (`src/sml_char.sml`) | `compare`, `contains`, `notContains`, `isLower`, `isUpper`, `isDigit`, `isGraph`, `isPrint`, `isCntrl`, `isAscii`, `isAlpha`, `isAlphaNum`, `isHexDigit`, `isSpace`, `isPunct`, `toLower`, `toUpper` |

These currently retain the types, argument order and results of the SML routines they came
from. That is their present implementation contract, not a constraint on the custom Basis. List predicates
short-circuit; mapping and application visit elements from left to right; `foldr` invokes
its callback from right to left. ListPair functions stop at the shorter input, as their
non-`Eq` SML counterparts do. The list and option modules call no host library functions. SmlChar needs only character
ordering/equality and `Num.String.size`, `Num.String.sub`, `Num.Char.ord`, `Num.Char.chr`.
Its guarded loops stay within string bounds; its case conversions call `chr` only with valid
ASCII codes. Characters outside ASCII are left unchanged by case conversion.

The compiler uses these source implementations in place of many host operations. During the
bootstrap, they have distinct names and are loaded explicitly, for example `SmlList.exists p xs`.
Legacy `List.exists` bindings in the checker still describe the host compatibility interface;
they are not automatically redirected to the source modules. Those interfaces and namespaces
need migration when the custom Basis API is settled.

`make wm` generates a `.wm` file next to each module, using the ordinary translator.
Consumers receive ordinary namespace imports, such as `from "./sml_list.wm" import * as SmlList`.
There are no special translation mappings for these modules. Compiler dependencies are in the build, self-check, watcher, round-trip suite and bootstrap
check. The old `SmlChar` port is excluded from the compiler build and `make wm`; its independent
regression test still translates it in a temporary directory.

The bootstrap host layer still supplies numeric adapters, string/character representation
operations, I/O and partial operations such as `List.last` and `Option.valOf`. Their existing
exception behavior belongs to that compatibility layer. For the custom Basis, fallible
operations should instead expose Result-based APIs; the inability to declare SML exceptions
is a reason to design these APIs, not a requirement to retain host exception functions forever.
The new collection modules already use the custom convention and Result-based failures.
The compiler has migrated classification and case conversion to `SubsetChar`; its older
collection ports and host compatibility interfaces still need migration.

`tests/basis/compare.sml` compares the current source algorithms to MLton's routines, including
callback order and short-circuiting. This is regression coverage for these implementations,
not a requirement that the future custom Basis match SML library signatures. The translated
`tests/basis/portable_basis.sml` runs with both MLton and Workman; `make test` includes Workman
checks when `wm` is installed. It validates this source graph, not the entire compiler or the
final custom Basis.

## Reused sources and character validation

`SmlChar` adapts classification and case-conversion routines from MLton's
`basis-library/text/char.sml` at `aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37`, and the linear
membership search from MLWorks' `src/basis/__pre_char.sml` at
`e6569f046c6cbff9d99e821b41daf56990f2a9b0`. These are the local sibling checkouts used for
the port. Copyright notices are retained in `sml_char.sml`; the licenses are included in
[MLton.txt](../LICENSES/MLton.txt) and [MLWorks.txt](../LICENSES/MLWorks.txt).

The port replaces `fun` with `val`/`val rec` and `fn`, removes functor/structure wrappers and
unsafe access, and uses real-valued code/index adapters. The membership search compares
characters directly instead of comparing their integer codes. SML's ASCII classification and
8-bit behavior remain unchanged; no Unicode classification or locale-specific casing is added.

`tests/char-basis.sh` compares original and round-tripped code to MLton for every byte-valued
character, including every pair for ordering and empty/repeated/control/high-byte membership
cases. It runs as part of `make test`. The historical port is not runnable in Workman: it
retains `LESS`, `String.sub` and `Char.ord`. The compiler uses `SubsetChar` instead, so these
compatibility dependencies require no new kernel operations. The custom library uses its own
ordering constructors and source byte operations.

`SubsetChar` adapts the same MLton classification rules and retains the MLton copyright
notice and license attribution. Its literal tables and checked ASCII ordering replace the
older range/code arithmetic implementation; it does not include the MLWorks string search.

## Open library questions

- Extend collection and string APIs above the implemented checked byte/index boundary.
- Refine and eventually freeze the implemented text and CLI kernel contracts.
- Migrate remaining compatibility interfaces and replace Workman's separate library.
- Consider immutable vectors and word-oriented modules if their required types become available
  in the language; library additions do not independently add language types.

## Minimal text boundary

The baseline uses ordinary byte sequences, source Unicode codecs and one extraction operation
for opaque native strings. String construction is portable through a complete literal table and
ordinary concatenation. `SubsetString` validates both directions; `SubsetSource` converts once
and supplies source-built indexing. Both compiler lexers now use it.

UTF-8, UTF-16LE and UTF-16BE are encoded/decoded in ordinary SubsetML over bytes and checked
scalar codes. JavaScript representation is not a language requirement. Bytes, Unicode scalars
and source/editor offsets retain separate contracts and the language's 8-bit semantics.

See [text-design.md](text-design.md) for the adapters and performance tradeoffs. The generated
compiler uses this text boundary plus the six CLI host operations; it checks, translates and
round-trips its own SubsetML source graph.

### Comparison with wm-mini frontend-v3

The sibling [frontend-v3](../../wm-mini/tooling/frontend-v3/README.md) is a useful existing
consumer to compare before selecting the boundary. Its source-reader needs are indexed:

| Operation | Current v3 implementation | Contract |
|---|---|---|
| Length | `.length`, cached in `Reader` | UTF-16 code-unit count |
| Numeric unit access | JS `String.prototype.charCodeAt` in `character.wm` | UTF-16 unit code; readers also probe beyond EOF |
| Single-unit lookahead | guarded `.slice(index, index + 1)` in `lexer/util.wm` | Optional one-unit string, not necessarily a Unicode scalar |
| Span extraction | `.slice(start.index, end.index)` | Text retaining original spelling in UTF-16 source coordinates |

V3's `character.wm` has a local `Char = String` alias; its numeric `codeAt` does not operate
on SubsetML's 8-bit `char` type. Literal readers combine surrogate pairs and reject lone
surrogates; valid character literals count Unicode scalars even though spans count UTF-16
units. `peekByOne` may therefore return half of a surrogate pair, which cannot be treated as
a scalar character. Some readers probe at or beyond EOF before checking bounds, relying on
the current host code-access behavior; a checked portable reader needs an explicit EOF policy.

SubsetML's compiler instead has byte offsets and eagerly builds decoded literal values.
V3 retains spelling through source spans and validates escapes without emitting their decoded
values yet. Consequently, v3 does not demonstrate that character-to-string construction can
be removed from the whole SubsetML compiler's needs.

The reusable part is the immutable reader containing a source and cached length, shared by
lookahead, advancing and span extraction. Classification, lexeme scanning, position updates and
literal validation can sit above a narrow source interface. An indexed reader can be built over
source byte storage; efficient host slices are optional acceleration rather than a minimal
kernel requirement.

Before sharing those algorithms, distinguish **source storage units**, **source offsets** and
**literal character values**. Directly adopting UTF-16 indexing or Unicode `Char` would change
SubsetML's current language contract. The current byte interface and a future Unicode/editor
source profile may need distinct adapters. V3's JS interop, `Result.debug` and unreachable
panics are host/invariant mechanisms to review during a port, not required general-purpose
SubsetML FFI features. Its debug entry point's directory walk is likewise a tooling dependency,
not evidence that the compiler kernel needs directory enumeration.

`tests/kernel-portable.sh` runs a focused compiler-core fixture on MLton and Workman.
Python integer arithmetic supplies independent natural division/formatting vectors through
2^53−1. The fixture checks list index/count errors and callback order, persistent map updates,
unification names, datatype elaboration, rejection of text ordering, and translation/parsing.
It excludes CLI execution. `tests/io-portable.sh` checks all byte values in files and both
output streams, argument/path marshalling, host errors, NUL paths and rejection before file
truncation. `tests/cli-portable.sh` compares the native and generated Workman compiler's check,
parse, format, round-trip and forward/reverse translation modes, including failure exits.
