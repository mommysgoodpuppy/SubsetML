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
association tables can be source algorithms. All custom modules except SubsetString make no direct qualified
host calls; SubsetString uses the one extraction operation. The source real comparator reports NaN as Unordered without host `Real.compare`.
Character literals/equality suffice for the new ASCII tables, even though the
current Workman operator `<` cannot compare characters.

## A practical first budget

With native immutable strings and hardware real numbers, a reasonable candidate is **7–10
library entry points beyond language operators**, using one native-string extraction operation. Counted individually, the families are:

| Family | Candidate operations | Count | What source can derive |
|---|---|---:|---|
| Text representation | native string to numeric codes | 1 | slices, explode/implode wrappers, concatenation, search, splitting, escaping, code-based comparisons |
| Numeric support | floor, finite-value test, real formatting | 0–3 additional | length/index loops, min/max, checked index validation, integer division/modulo with defined ranges; source formatting may replace the formatter |
| Host/process | arguments, read whole file, write whole file, write stdout, write stderr, exit | 6 | the compiler's command-line driver and diagnostics |

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

The file operations should return Result, with typed errors and documented encoding, byte/text,
file replacement and short-write behavior. Reading/writing whole files avoids exposing stream
handles, close operations and exception recovery to the initial compiler. `writeStdout` and
`writeStderr` should write exactly their input; a source `writeLine` can add a newline.
Targets without a process can receive source text and return output through an embedding API,
so the six host entry points belong to a command-line profile rather than every Basis program.

## Evidence from the current compiler

The compiler currently uses a much broader bootstrap interface. Its actual needs separate as
follows; these observations come from the source, not a claim about all SML implementations.

| Current source | Bootstrap dependencies | Migration direction |
|---|---|---|
| `src/lexer.sml`, `src/wm_lexer.sml` | SubsetSource, CompilerText, SubsetChar, real arithmetic/equality | migrated to SubsetSource/CompilerText; source lookup, slices and literal decoding |
| `src/print.sml`, `src/sml_print.sml`, `src/wm_print.sml` | character/string escaping, concatenation, numeric formatting | source escaping/builders; settle code access and real formatting contracts |
| `src/doc.sml` | SubsetSource, source trimming/splitting/repetition, real comparisons | migrated; renderer graph checks and runs in Workman |
| `src/parser.sml` | source text conversion/concatenation, portable SmlList/SmlOption, numeric comparison | parser graph checks and runs in Workman; tuple patterns use explicit fields |
| elaborator, normalization and translation | list/option routines, numeric list indices/lengths, min/max and comparison | custom source collections; explicit index errors and real contracts |
| `src/main.sml` | `TextIO.openIn/inputAll/closeIn/openOut/output/closeOut/stdErr`, `print`, `CommandLine.arguments`, `OS.Process.exit/success/failure` | six host operations above; stream mechanics stay inside adapters |

`lib/num.sml` currently uses MLton integers, exceptions and full-SML functions behind its
real-valued interface. Those implementation details are bootstrap scaffolding, not intrinsic
requirements for a future SubsetML compiler. Replacing partial calls requires auditing callers
and handling their Result values; renaming bindings alone is insufficient.

There are two remaining kinds of self-hosting work. First, running the generated translator/
checker in Workman needs migration away from unresolved bootstrap libraries and target support
for the eventual kernel. Second, native self-hosting needs a code generator and runtime; these
are not implemented yet. A compiler that emits artifacts can use an external build/link step:
self-hosting does not require it to launch a compiler, dynamically load code or expose an FFI.
`make bootstrap-check` currently validates SubsetML → Workman → SubsetML and rebuilds with MLton;
it does not establish execution of the whole compiler in Workman or a native backend.

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
Only implemented extraction is listed there; candidate numeric and host/process entries remain
provisional.
