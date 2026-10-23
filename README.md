# SubsetML

SubsetML's language is a strict subset of Standard ML as given by *The Definition of Standard
ML (Revised)*. Language semantics stay SML-compatible when the same library environment is supplied.
The [language specification](docs/spec.md) and the [SubsetML Basis](docs/basis.md) are separate
specifications. The Basis is a custom portable library inspired by SML, rather than an
implementation of the SML Basis Library.

It is meant to be:

- the common language of [Workman](../wm-mini) and SML, and a portability layer for Workman;
- a route for compiling Workman code with MLton;
- a target for a native compiler that is simpler than full SML compilers, since it omits
  references, exceptions, functors, signatures and the rest of the list in the spec.

SubsetML includes a signed 32-bit `int` alongside `real`. Integer literals, equality,
patterns, checked arithmetic, `div`/`mod` and numeric defaulting follow SML semantics,
with a fixed range across targets. This expands the previously real-only subset;
see the [integer specification](docs/integers.md). WM/JS integer execution remains deferred.
The compiler and indexed Basis APIs now use integers; see the
[migration status and PS2 memory result](docs/integer-migration.md).
The [MLWorks/PS2 workflow](docs/mlworks-ps2.md) stages a WM-authored host I/O
probe for native compilation and execution, with filesystem failures returned as Result values.
The [SML target plan and commands](docs/sml-targets.md) share target adapters
between MLton and MLWorks and provide reusable native source-list staging.
The [MLWorks batch/image workflow](docs/mlworks-batch.md) runs the full compiler
on PS2, translating WM locally and executing the generated SML. Compiler
objects can now also be built entirely on the PS2 using MLWorks'
`-gc-low-memory` policy (17,012 KiB peak RSS for the clean 42-unit build).
For library APIs, dependencies and bootstrap
migration, see the [SubsetML Basis documentation](docs/basis.md), with the
[candidate self-hosting kernel](docs/self-hosting-kernel.md) and
[minimal byte/Unicode text design](docs/text-design.md) documented alongside it.
The Basis docs describe the [error procedure pattern](docs/basis.md#error-procedures),
with a runnable [errordemo.sml](errordemo.sml) and a comparison to Workman's error ergonomics.
Lossless UTF-16 editor/source storage is provided by `SubsetUtf16Source`, with indexed lookup,
shared slice views and strict conversions; it preserves lone surrogate units without expanding
the language or host kernel. Run `sh tests/utf16-source.sh` for its cross-target checks.
The [source module-loading plan](docs/module-loading-plan.md) describes implemented comment-based
entry-file checking with Workman-aligned resolution, and the remaining backend generation work.
The [frontend-v3 native portability decisions](docs/frontend-v3-native.md) record the proposed
MLton integration target, agreed lowerings and open questions. The
[Result carrier investigation](docs/carrier-portability.md) checks which generic error patterns
work in MLton and where record lowering needs refinement. The
[carrier lowering design](docs/carrier-lowering.md) documents the implementation and remaining
typed transformations in detail.

SubsetML is implemented in SubsetML. The sources in `src/` are SubsetML, so for now MLton builds
them, and `make selfcheck` has the implementation check its own source.

## Status

| Part | State |
|---|---|
| Lexer and parser with the fixed infix table (`src/lexer.sml`, `src/parser.sml`) | done |
| SubsetML ⇄ Workman translation (`src/wm_*.sml`, `src/translate.sml`, [docs/translation.md](docs/translation.md)) | done |
| Elaboration (`src/elab.sml`): types, equality, overloading, value restriction, explicit type variables, records (R2, R3, `#lab`), B1, F2 | done; match exhaustiveness warnings missing |
| Native SML emission with explicit signed Int32 semantics | implemented (`native`) |
| Evaluation / machine-code backends | not started |

Single-entry `check` loads the explicit import graph and checks each module against the initial
environment plus its declared dependencies. Multiple supplied files retain legacy sequential
checking against the bootstrap compatibility environment in `src/basis.sml`. `tests/edge/` checks
language conformance under that environment; it does not establish SML Basis Library support.

## Usage

```sh
make                              # builds bin/subsetml with MLton
bin/subsetml check ENTRY.sml      # loads explicit comment imports and checks the module graph
bin/subsetml check FILE1 FILE2 ...# legacy source-list checking in declaration order
bin/subsetml parse FILE...        # prints the abstract syntax
bin/subsetml native OUTDIR FILE.sml... # emits explicit Int32-targeted native SML
bin/subsetml fmt FILE...          # reprints as SubsetML
bin/subsetml wm OUTDIR FILE...    # translates to Workman (one module per file)
bin/subsetml sml OUTDIR FILE.wm...# translates Workman back to SubsetML
bin/subsetml sml-entry OUTDIR ENTRY.wm # discovers and translates the entry import graph
make test                         # self-check, tests, and translation round trips
make wm                           # writes src/foo.wm next to each src/foo.sml
make wm-selfcheck                  # generated Workman compiler checks its own SubsetML sources
make watch                        # keeps src/*.wm in sync while you edit
make custom-basis-check           # custom library contracts, translation and Workman execution
make text-basis-check             # byte readers and strict UTF codecs against reference vectors
make bootstrap-check              # src -> Workman -> SML, then builds and runs the result
```

Every program under `tests/accept` must also type-check with `mlton -stop tc`, with the bootstrap adapters supplied, checking its SML language compatibility. Each `src/foo.wm` is generated for reading side by side and executing in Workman. `make wm` stages the text extraction and
file/process adapters from `lib/`, replacing their generated host declarations.
Run the generated compiler with `wm run src/main.wm -- check FILE...`.
String construction, byte indexing and codecs come from shared SubsetML source.
Edit the `.sml` files; the `.wm` files are overwritten.
