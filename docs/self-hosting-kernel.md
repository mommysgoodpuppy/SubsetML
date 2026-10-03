# Candidate self-hosting kernel

This is a design inventory, not an implemented primitive ABI or a proof of minimality.
The [Basis portability rule](basis.md#portability-rule) requires source implementations for
anything reasonably expressible in the language. Reserve target code for operations
that need representation access or interaction with the host. A smaller language syntax does
not by itself determine how many runtime primitives are necessary.

## Count language support separately

A backend must implement functions/closures, calls, recursion, immutable datatype/list/tuple/
record values, pattern matching, allocation and memory management. It must also implement the
language's numeric operators, equality where permitted, literals, and required behavior for
failed matches. These costs exist even when a module has no explicit kernel calls. They are
not extra List, Option or Result entry points in the custom Basis.

Substring, collection traversal, ASCII classification, escaping, formatting integers and
association tables can be source algorithms. The algorithm modules make no direct qualified host calls; SubsetString uses one extraction
operation, while SubsetIo and SubsetProcess expose the six-operation CLI host profile. The source real comparator reports NaN as Unordered without host `Real.compare`.
Character literals/equality suffice for the new ASCII tables, even though the
current Workman operator `<` cannot compare characters.

## A practical first budget

With native immutable strings and hardware real numbers, the implemented compiler CLI uses
**8 library entry points beyond language operators**: one native-string extraction operation,
six host/process operations, and filesystem path canonicalization. Extra numeric entry points remain candidates for a broader
library, rather than requirements of the current compiler. Counted individually, the families are:

| Family | Candidate operations | Count | What source can derive |
|---|---|---:|---|
| Text representation | native string to numeric codes | 1 | slices, explode/implode wrappers, concatenation, search, splitting, escaping, code-based comparisons |
| Numeric support | floor, finite-value test, real formatting | 0–3 additional | length/index loops, min/max, checked index validation, integer division/modulo with defined ranges; source formatting may replace the formatter |
| Host/process | arguments, read whole file, write whole file, write stdout, write stderr, exit | 6 implemented | the compiler's command-line driver and diagnostics |
| Filesystem identity | canonical absolute path, resolving symlinks | 1 implemented | import graph traversal and caching; lexical normalization remains source code |

The [module-loading implementation](module-loading-plan.md) uses the canonical-path operation
to preserve Workman's filesystem module identity, including symlinks. It is included in the
eight-entry-point count. Graph traversal and import handling remain source code.

The numeric row is provisional: floor and finite testing may be provided as language/runtime
intrinsics, and formatting may be source code. Moving a function between the language and
library columns changes this count without reducing implementation work. This budget assumes
basic numeric comparison/equality is already implemented by the backend. Real equality must
have an explicit binding/convention because SML `real` is not an equality type.

This is an engineering starting point, not an irreducible lower bound. A character-list string
representation can eliminate indexed native-string access; the implemented exhaustive byte table already supplies checked code conversion in source.
Code conversion no longer adds primitive entry points. Opaque native-string extraction remains a representation boundary; the [minimal text design](text-design.md) makes indexed native access optional. Conversely, efficient binary output or streaming large inputs may justify a byte buffer
or streaming interface later. No array, reference, mutable hash table, general FFI, subprocess,
clock or directory-enumeration API is required by the present compiler algorithm.

The implemented file operations return Result, with typed errors and documented byte/text,
file replacement and short-write behavior (see the Basis I/O profile). Reading/writing whole files avoids exposing stream
handles, close operations and exception recovery to the initial compiler. `writeStdout` and
`writeStderr` write exactly their input; a source `writeLine` can add a newline.
Targets without a process can receive source text and return output through an embedding API,
so the six host entry points belong to a command-line profile rather than every Basis program.

## Evidence from the current compiler

The compiler uses source implementations for library algorithms and eight explicit host entry
points. Its dependencies separate as follows; these observations describe this compiler, not
all SML implementations.

| Current source | Dependencies | Implementation |
|---|---|---|
| `src/lexer.sml`, `src/wm_lexer.sml` | SubsetSource, CompilerText, SubsetChar, real arithmetic/equality | migrated to SubsetSource/CompilerText; source lookup, slices and literal decoding |
| `src/print.sml`, `src/sml_print.sml` | shared SML byte escaping and concatenation | migrated to source; SML printer graph checks and runs in Workman |
| `src/wm_print.sml` | source byte conversion, concatenation, character tables and bounded hex arithmetic | migrated; printer graph checks and runs in Workman without native string indexing or numeric div/mod |
| `src/doc.sml` | SubsetSource, source trimming/splitting/repetition, real comparisons | migrated; renderer graph checks and runs in Workman |
| `src/parser.sml` | source text conversion/concatenation, portable SmlList/SmlOption, numeric comparison | parser graph checks and runs in Workman; tuple patterns use explicit fields |
| types, integer map, unification, environments, elaborator, bootstrap environment, normalization and translation | source lists, exact-natural arithmetic, byte text operations | compiler core checks and runs in Workman; no numeric formatter, floor/div/mod helper or native text indexing |
| `src/main.sml` | SubsetIo whole-file byte reads/writes, stdout/stderr; SubsetProcess arguments and exit | six host operations above; stream mechanics stay inside adapters |

`lib/num.sml` currently uses MLton integers, exceptions and full-SML functions behind its
real-valued interface. Those implementation details are bootstrap scaffolding, not intrinsic
requirements for a future SubsetML compiler. Replacing partial calls requires auditing callers
and handling their Result values; renaming bindings alone is insufficient.

The generated translator/checker runs in Workman using the staged kernel adapters. Checking
and translating the compiler itself also requires its recursive algorithms to work within the
target runtime. Native self-hosting still needs a code generator and runtime; these are not
implemented yet. A compiler that emits artifacts can use an external build/link step:
self-hosting does not require it to launch a compiler, dynamically load code or expose an FFI.
`make bootstrap-check` currently validates SubsetML → Workman → SubsetML and rebuilds with MLton;
it does not establish execution of the whole compiler in Workman or a native backend.
`make wm-selfcheck` runs the generated compiler against its complete SubsetML source graph.
The generated compiler also reproduces the native compiler's Workman output byte for byte,
excluding the two generated host declarations that staging replaces with target adapters.
Running its `roundtrip` command on the complete source graph also succeeds. Direct tail-call
scanning and accumulator-based item parsing avoid token-count stack growth. Deeply nested
AST elaboration still uses ordinary recursion and can exceed Workman's JavaScript stack;
removing that limit would require source traversal changes, not another host operation.

## Contracts to settle before freezing the ABI

- Preserve the language's 8-bit character contract ([spec §2](spec.md)). Decide how target
  Unicode text is encoded or rejected at I/O boundaries, and specify byte-based indices.
  The source code converters already enforce codes 0–255; text primitives must enforce the
  same character domain.
- Give indices/counts exact bounds. With real-only numbers, NaN, infinity, negative/fractional
  indices and values beyond exact integer representation must be addressed explicitly.
- Define numeric equality, non-finite arithmetic, floor/division behavior, and formatting. Do
  not inherit accidental differences between MLton and Workman.
- Define Result-based I/O errors and exact output behavior, then implement thin target adapters.
- Migrate compiler callers and run the generated compiler against the same corpus before
  describing the target as self-hosted.

UTF-8 and UTF-16 handling belongs in source above byte storage, rather than in this kernel.
The bridge count can fall to zero on a backend that represents strings directly as ordinary
byte sequences; host I/O remains separate. Source codecs/readers, string construction and extraction adapters are implemented and tested.
Both lexers now convert native input once and use the source-built byte index.

The executable module dependency inventory remains [basis-dependencies.json](basis-dependencies.json).
Implemented extraction and CLI host operations are listed there; candidate numeric entries remain
provisional.

The generated CLI now checks and runs in Workman using SubsetIo and SubsetProcess.
File access, exact standard-output/error writes, arguments and exit are the six host operations
in `lib/subset_host.*`; checked byte conversion, path validation and diagnostics are source
algorithms. The CLI no longer imports TextIO, CommandLine or OS.Process.
