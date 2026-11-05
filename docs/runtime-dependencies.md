# Runtime and SML Basis dependency audit

Updated 2026-10-29. This is the porting contract for an implementation of SubsetML
from scratch. The custom Basis is source code, not an obligation to implement the
SML Basis Library. Language conformance and library availability are separate:
removing initial library bindings does not change the meaning of accepted SML.

## Enforcement

`bin/subsetml check-portable ENTRY.sml` checks the entry's explicit dependency
graph with no SML Basis structures or convenience functions. A list of files is
checked sequentially under the same restricted environment. Locally implemented
values with SML names remain legal; this is semantic environment restriction,
not a spelling blacklist. Qualified references, aliases and `open` cannot obtain
a missing host structure. Imported source uses the same restricted environment.

`make selfcheck` requires this profile for all custom Basis modules, including
WON and the checker declarations for host adapters. It also audits the dependency
inventory, the runtime-operation justifications below, and profile regressions.
The existing `check` command retains the compatibility environment for SML ports
and compiler bootstrap work. Passing that command alone is not a portability claim.

The source-only `SmlList`, `SmlListPair` and `SmlOption` compatibility algorithms
are not calls to a host SML implementation. Their APIs can migrate separately.

## Primitive initial environment

| Facility | Why it remains; source alternative |
| --- | --- |
| `unit`, `bool`, `int`, `real`, `char`, `string`, `list`; `true`, `false`, `nil`, `::` | Representation and typing baseline. Lists are required by SML derived forms. Option is now an ordinary source datatype, not part of this initial environment. |
| `=`, `<>` | Equality over admissible types requires representation-aware compiler/runtime support. No host comparison library is required. |
| `+`, `-`, `*`, `~`, `<`, `>`, `<=`, `>=`, integer `div`, `mod`, real `/` | Numeric representation operations with SML semantics and signed 32-bit integers. A backend implements operations directly; it need not supply SML numeric structures. Fault behavior remains the runtime's responsibility. |
| `^` | Native string construction/concatenation primitive. Strings cannot be inspected or constructed from characters using the core language alone. Construction through the text adapter is an alternative, but the current source uses native concatenation directly. No benchmark claim is made for choosing between those interfaces. |

Bare `not`, `abs`, `@`, `print`, `map`, `rev`, folds, string conversions and the
other compatibility pervasives are excluded. `order` and its SML constructors
are excluded; `SubsetOrder` declares its own datatype. `SubsetBool.not` replaces
the custom Basis's former bare `not` uses.

## Source-owned option

`SubsetOptionValue` declares `datatype 'a option = NONE | SOME of 'a` in ordinary
source. `check-portable` supplies neither the type nor its constructors; consumers
import and open that module. This adds no native runtime operation or SML Basis
dependency. It is separate from `SubsetOption` helpers to avoid a cycle:
`SubsetResult.toOption` needs the datatype, while `SubsetOption.toResult` needs
Result. Both depend on the independent datatype module.

Compiler source and the old source-only list/option helpers use this datatype too.
The compatibility checker retains SML's initial `option` for external fixtures;
that is a separate nominal type. Full-SML comparison tests convert explicitly
at their boundary. Native SML's `Int32` shim can still use its host `SOME` without
making host option a dependency of authored portable source.

Workman's generated datatype is marked `@basis-type Option`, just as Result is
marked `@basis-type Result`: it adopts WM's existing Option identity so FFI and
bare `Some`/`None` continue to interoperate. This WM integration does not make the
SubsetML datatype special or restore it to the portable initial environment.

## Explicit adapter operations

These are the only qualified host operations declared by the custom Basis.
An adapter entry point is not necessarily an external dependency on every target:
the inventory records calls from portable source, while the target determines
whether each call needs runtime support or is an identity operation.
`tests/basis/dependencies.py` checks this table against the inventory. A new
operation needs an implementation-independent contract, a source alternative,
and a necessity or measured performance justification. Do not claim something
is too slow without evidence. Domain validation and typed errors stay in source.

| Operation | Motivation and source alternative |
| --- | --- |
| `SubsetTextHost.codes` | Read native string storage as integer units. Core SML has no string destructuring, so some representation-aware extraction is necessary. An indexed access primitive would be an alternative interface. |
| `SubsetTextHost.fromCodes` | Construct a native string from units. Character-to-string tables plus `^` are a source alternative. The combined character/construction table scans dominated the measured WON workload: 517 KB took 10.8 s, about 9.8 s in scans; constant-time conversions reduced it to 1.7 s. See basis.md, Byte character codes. |
| `SubsetTextHost.charCode` | Byte-character code conversion. A 256-entry source scan works and remains in the checker reference implementation; retained as a primitive for the same measured text-processing cost. |
| `SubsetTextHost.codeChar` | Inverse byte-character code conversion. A source table lookup works; retained for the same measured cost. Source wrappers check the byte range. |
| `SubsetTextHost.encodeUtf8` | Bridge host text representation to a UTF-8 byte string. Identity for byte-native SML targets. JS uses host text conversion; implementing this from storage units and the existing source codecs is possible. This is a representation-adapter choice, not a claim that UTF-8 requires host library support. |
| `SubsetTextHost.decodeUtf8` | Inverse host text bridge. Identity on byte-native SML targets; JS reconstructs its native text representation. Source validates UTF-8 first. Construction from decoded units is an alternative; no measured performance requirement is asserted. |
| `SubsetHost.canonicalPath` | Filesystem identity including symlinks requires host information. Lexical source normalization cannot replace it. |
| `SubsetHost.readFile` | Obtain external file bytes. Impossible in the pure language alone; buffering and OS APIs belong to the target adapter. |
| `SubsetHost.writeFile` | Write external file bytes. Requires a host side effect; conversion and path validation remain source operations. |
| `SubsetHost.writeStdout` | External output requires a host side effect. Does not require implementing SML TextIO. |
| `SubsetHost.writeStderr` | External diagnostic output requires a host side effect; separate from stdout so callers choose the channel. |
| `SubsetHost.arguments` | Obtain process invocation arguments. Not available through pure source computation. |
| `SubsetHost.status` | The host's process status. The adapters hold an exit code: MLton's `OS.Process.system` returns a raw wait status that its own `exit` rejects, so the SML adapters recover the code with `Unix.fromStatus` and leave through `Unix.exit` for codes other than 0 and 1. A child killed by a signal becomes `failure` there and 128 plus the signal number on JS. |
| `SubsetHost.success` | The status of successful termination. See `SubsetHost.status`. |
| `SubsetHost.failure` | A status of failed termination. See `SubsetHost.status`. |
| `SubsetHost.isSuccess` | Whether a status denotes success. A source comparison would need the adapters' representation to be public. |
| `SubsetHost.system` | Run a command through the host's shell. Not available through pure source computation. The compiler doesn't use it. |
| `SubsetHost.getEnv` | Read an environment variable. Not available through pure source computation. The compiler doesn't use it. |
| `SubsetHost.terminate` | Terminate the process without exit actions, following `OS.Process`. Equivalent to `exit` until `atExit` exists. |
| `SubsetHost.exit` | Terminate the process. Source recursion cannot provide process termination; this also supports invariant panic. |

## Representation bridges: dependencies that vary by target

`encodeUtf8` and `decodeUtf8` are specifically **JS host conversion dependencies**
in the current implementations, not requirements to implement SML UTF-8 Basis
functions. Their shared adapter names let portable source use the same interface
on targets with different native string representations.

| Entry point | SML host | JS host | New native SubsetML implementation |
| --- | --- | --- | --- |
| `SubsetTextHost.encodeUtf8` | Identity (`fn value => value`); no SML Basis call. Host text is supplied as UTF-8 bytes by convention. | Converts UTF-16 host text to a UTF-8 byte string, currently using `String.prototype.isWellFormed`, `encodeURIComponent` and `unescape`. | Identity if host text already uses UTF-8 bytes; conversion support only if its representation differs. |
| `SubsetTextHost.decodeUtf8` | Identity (`fn bytes => bytes`); no SML Basis call. | Converts a validated UTF-8 byte string into JS UTF-16 text, currently using `escape` and `decodeURIComponent`. | Identity for UTF-8-native text; otherwise adapt to that target's representation. |

SML strings are arbitrary byte strings, not intrinsically valid UTF-8.
`SubsetText.toUtf8` and `fromUtf8` validate with the source-written
`SubsetUtf8.decode` on **both** targets. Identity in the adapter does not skip
validation. Likewise, scalar-to-byte `SubsetUtf8.encode` is portable source code;
it does not require a host UTF-8 codec on either target.

Keep this distinction when adding other representation bridges: document the
actual dependency per target, and do not count an identity implementation as a
new runtime primitive obligation. The operation inventory intentionally retains
these shared entry points even where they introduce no host dependency.

## Existing SML adapter implementation dependencies

The following are dependencies of the adapters shipped for existing SML systems,
not additional requirements on a native SubsetML implementation. A new backend
supplies the operations above using its own representation and OS bindings,
with identity implementations for bridges that its representation does not need. The
portable profile deliberately does not admit these adapter implementations as
authored SubsetML: they use full SML, including exceptions.

| Adapter | Real SML Basis dependencies | Assessment |
| --- | --- | --- |
| `lib/subset_text_host.sml` | `Char.ord`, `Char.chr`; `Int32.fromInt`, `Int32.toInt`; `List.map`; `String.explode`, `String.implode` | Character access and integer-width adaptation implement the text boundary. List mapping is replaceable source recursion; explode/implode package host string access and construction. Convenience use in this adapter does not justify exposing these structures to portable source. |
| `lib/subset_host.sml` | `General.exnMessage`; `OS.FileSys.fullPath`; `BinIO.openIn`, `inputAll`, `closeIn`, `openOut`, `output`, `closeOut`; `Byte.bytesToString`, `stringToBytes`; `Word8Vector.length`; `Word8VectorSlice.slice`; `Posix.FileSys.stdout`, `stderr`; `Posix.IO.writeVec`; `CommandLine.arguments`; `OS.Process.exit`, `success`, `failure` | Existing MLton implementation of filesystem, binary I/O and process operations. Vector/slice and byte conversions bridge that target's I/O representation; partial-write handling is necessary. Other targets can implement the same boundary without these structures. |
| `lib/sml-basis/subset_host.sml` | Same BinIO, Byte, General, CommandLine and process calls; `OS.FileSys.fullPath`, `mkDir`, `rmDir`, `remove`, `rename`, `isDir`, `openDir`, `readDir`, `closeDir`; `TextIO.output`, `flushOut`, `stdOut`, `stdErr`; `String.explode`; `List.exists`, `rev` | Wider existing SML/MLWorks adapter, including filesystem operations for tooling beyond the portable Basis inventory. List predicates/reversal are replaceable source helpers; stream flush and resource handling express target side effects. The extra filesystem calls are not baseline Basis requirements. |

`lib/num.sml` is legacy compatibility scaffolding, not a custom Basis dependency.
It uses Real conversion/classification/formatting, Int/LargeInt parsing and
formatting, IEEEReal rounding modes, Option helpers, and String/List/Char/
CharVector operations through captured Basis aliases. A native implementation
does not owe this interface. Keep it outside the portable source profile.

## Compiler source portability

As of 2026-10-30, the full compiler passes `check-portable`, both as a sequential
source list and through `src/main.sml`'s explicit entry graph. `make selfcheck`
requires both forms. `make wm-selfcheck` checks the same strict entry graph with
the generated WM compiler. `make bootstrap-check` additionally rebuilds the compiler
through SML -> WM -> SML and requires the rebuilt compiler to pass the strict
entry check. CLI tests also verify rejection of SML Basis access
under this profile on both backends.

Inherited `@` uses have been replaced by source `SubsetList.append`/`concat`;
bare `not` uses now call `SubsetBool.not`. No new primitive or initial binding
was introduced. The compiler build and bootstrap MLB no longer load `lib/num.sml`.
That file remains available only to legacy SML compatibility fixtures.

The large table in `src/basis.sml` describes the compatibility environment the
compiler can check; it does not supply the environment used to self-check compiler
source. Existing SML compatibility fixtures and the standalone `SmlChar` port can
still use `check`; they are not part of the portable compiler entry graph.
Native SML emission's `Int32` shim remains a target implementation detail, not a
portable source requirement.

## Upkeep

For any new host dependency, update `basis-dependencies.json`, this operation
table and the adapter contract, then run `make selfcheck`. Prefer source code
unless the operation needs external state, native representation access, or a
documented performance exception. Audit conveniences inside adapters separately
from runtime obligations. Keep compatibility fixtures and host adapters out of
the strict authored-source set; keep every custom Basis module in that set.
