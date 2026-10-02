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

SubsetML currently omits `int`; numbers use `real`. For library APIs, dependencies and bootstrap
migration, see the [SubsetML Basis documentation](docs/basis.md), with the
[candidate self-hosting kernel](docs/self-hosting-kernel.md) and
[minimal byte/Unicode text design](docs/text-design.md) documented alongside it.

SubsetML is implemented in SubsetML. The sources in `src/` are SubsetML, so for now MLton builds
them, and `make selfcheck` has the implementation check its own source.

## Status

| Part | State |
|---|---|
| Lexer and parser with the fixed infix table (`src/lexer.sml`, `src/parser.sml`) | done |
| SubsetML ⇄ Workman translation (`src/wm_*.sml`, `src/translate.sml`, [docs/translation.md](docs/translation.md)) | done |
| Elaboration (`src/elab.sml`): types, equality, overloading, value restriction, explicit type variables, records (R2, R3, `#lab`), B1, F2 | done; match exhaustiveness warnings missing |
| Evaluation / backends | not started |

`check` type-checks the files in order as one program, against the current bootstrap compatibility environment
in `src/basis.sml`. `tests/edge/` checks language conformance under that environment; it does
not establish SML Basis Library support.

## Usage

```sh
make                              # builds bin/subsetml with MLton
bin/subsetml check FILE...        # reports the first error in each file
bin/subsetml parse FILE...        # prints the abstract syntax
bin/subsetml fmt FILE...          # reprints as SubsetML
bin/subsetml wm OUTDIR FILE...    # translates to Workman (one module per file)
bin/subsetml sml OUTDIR FILE.wm...# translates Workman back to SubsetML
make test                         # self-check, tests, and translation round trips
make wm                           # writes src/foo.wm next to each src/foo.sml
make watch                        # keeps src/*.wm in sync while you edit
make custom-basis-check           # custom library contracts, translation and Workman execution
make text-basis-check             # byte readers and strict UTF codecs against reference vectors
make bootstrap-check              # src -> Workman -> SML, then builds and runs the result
```

Every program under `tests/accept` must also type-check with `mlton -stop tc`, with the bootstrap adapters supplied, checking its SML language compatibility. Each `src/foo.wm` is generated for reading side by side. The exception is
`subset_text_host.wm`: `make wm` stages its single extraction adapter from `lib/`.
String construction, byte indexing and codecs come from shared SubsetML source.
Edit the `.sml` files; the `.wm` files are overwritten.
