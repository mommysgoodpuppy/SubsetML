# SML targets and target adapters

Update: the [integer migration](integer-migration.md) removes the compiler's
real-arithmetic dependency. The numeric preflight discussion below records
the earlier investigation; current compiler staging no longer requires or
copies `check-real.sml`.
The [MLWorks batch/image experiment](mlworks-batch.md) tests a smaller object
graph and application-image restart with OS-enforced allocation limits.
It now also provides a working full compiler image on PS2, built from
emulator-produced objects. Local WM translation and generated-SML execution
are verified. MLWorks' subsequent `-gc-low-memory` runtime policy also permits
a clean native rebuild of all 42 reachable SubsetML compiler units on the PS2,
at 17,012 KiB peak RSS without swap.

## Plan

SML is a first-class output family. MLton and MLWorks share generated SML and
the source-implemented SubsetML Basis. Target adapters bridge the small
SubsetML interfaces to the standard SML Basis. They translate host exceptions
into Result values; authored SubsetML gains no exception syntax.

Most file, string and process APIs are standardized by the SML Basis. Share
their adapter implementations where their contracts agree. Keep differences
in compiler startup, build files, Basis loading, integer representation and
older implementation behavior explicit. Do not duplicate the portable Basis
or introduce a separate compiler implementation for each target.

The compiler kernel uses native-string extraction plus canonical paths,
whole-file reads/writes, stdout/stderr, arguments and exit: eight explicit
entry points beyond the language machinery supplied by the SML implementation.
Pakman's directory, subprocess, download and hashing operations are an
additional application profile, not prerequisites for compiling SubsetML.

Implement in this order:

1. Share the standard SML Basis host/text adapters and retain byte-exact I/O
   and Result errors. Keep the existing JS adapter outside this work.
2. Add reusable SML target staging to the SubsetML compiler. Validate the
   complete source list before writing output, apply signed Int32 lowering,
   and select native adapters explicitly by canonical checker identity.
3. Emit an MLton MLB or an MLWorks source loader. Load the MLWorks Basis once
   to preserve abstract type sharing. Give its loader explicit application
   arguments instead of confusing them with listener arguments.
4. Stage the compiler's own source graph and run check/translation commands
   on the real PS2. Record compatibility failures, numeric correctness and
   memory limits; a successful tiny application does not prove this milestone.
5. Connect WM entry-graph staging to the same target machinery while retaining
   canonical module identity, private imports and once-only initialization.
   Port pakman in WM and support local translation of its package code.

The initial staging interface may use explicit ordered SML source lists, as
the existing native emitter does. Build integration must not pretend to be a
general MLB-to-MLWorks converter. Native adapter implementations are full SML
and are checked by their SML compiler and contract tests, not by the SubsetML
source checker. Their supplied structure/type identity must match the checker.

The first acceptance test is: the PS2-hosted SubsetML compiler reads a tiny
WM file and writes its translated SML locally. Desktop translation remains
useful during bootstrap, but does not satisfy that native compiler milestone.

Current risks are MLWorks' reserved extension words (including `require`),
real-valued compiler indices, exact Int32 behavior, coherent Basis loading,
and approximately 27 MiB of PS2 RAM without swap. Integer migration of the
compiler internals is a separate change; do not silently narrow real to float32.

## Implemented source-list interface

```sh
subsetml sml-target mlton OUTDIR [--adapter CHECKER.sml NATIVE.sml]... FILE.sml...
subsetml sml-target mlworks OUTDIR [--adapter CHECKER.sml NATIVE.sml]... FILE.sml...
```

The output directory must exist. Supply checked SubsetML files in dependency
order. Each keeps its basename. Duplicate basenames and reserved build-file
names are rejected. All parsing, typechecking, adapter selection and native
adapter reads complete before any outputs are written. This is validation
before publication, not a filesystem transaction if a later write fails.

The generated `prelude.sml` fixes `int` to signed Int32 independently of the
target's ordinary integer width. MLton receives `project.mlb`; compile it with
`mlton -output PROGRAM OUTDIR/project.mlb`. MLWorks receives `bootstrap.sml`
and `load.sml`. From its target-objects directory, load `bootstrap.sml` once,
change to OUTDIR, `use "load.sml"`, then call:

```sml
SubsetTarget.load ["application", "arguments"];
```

The loader binds the standard `CommandLine.arguments` interface to that
explicit argument list before loading the application modules. This uses
full-SML reference state only in the startup adapter. It does not change the
SubsetML language or introduce shared mutable state into the portable Basis.
This is a fresh-process source loading workflow; saved application images and
incremental reload semantics are not implemented.

`--adapter` matches the canonical identity of a checker in the supplied source
list. Symlink aliases match; unrelated basenames do not. Missing selections,
duplicate selections and unreadable native sources are rejected. The native
file must export the same structures/types the checker promised. The target
compiler checks native use sites; contract tests verify the adapter behavior.
An automatically generated signature enforcing every unused checker member
is not implemented.

The shared host implementation is `lib/sml-basis/subset_host.sml`; both new
targets use the same standard Basis binary-file and flushed TextIO code on
Unix. It includes the directory operations tested for pakman. The old
`lib/mlworks/subset_host.sml` path is a compatibility symlink to it. The
existing `lib/subset_host.sml` retains its MLton/POSIX stdout implementation
for older build/test entry points. Native text extraction is shared in
`lib/subset_text_host.sml`.

## Bootstrap the compiler

```sh
python3 scripts/stage-sml-compiler.py mlton /tmp/subsetml-mlton
mlton -output /tmp/subsetml-mlton/run /tmp/subsetml-mlton/project.mlb
python3 scripts/stage-sml-compiler.py mlworks /tmp/subsetml-mlworks
```

The helper takes source order from the compiler's existing flat MLB manifest,
substitutes checked host/text declarations, and invokes SubsetML's own
`sml-target` command. It is bootstrap orchestration, not the implementation of
target generation and not a general MLB parser. Native targets use the shared
host and text adapters explicitly. The old `Num` compatibility module is not
needed by this staged compiler graph. `Unify.require` has been renamed to
`requireKind`, removing the known MLWorks extension-keyword conflict.

On MLWorks, pass ordinary compiler arguments to `SubsetTarget.load`, for
example `["sml", "out", "tiny.wm"]`. The compiler's existing entry point
reads them through the shared host adapter. Successful desktop rebuilding
does not establish that the complete compiler fits or runs correctly on PS2.
The compiler staging helper also copies `check-real.sml`. Run
`use "check-real.sml"` after loading the Basis and before loading the compiler;
it reports individual numeric checks and exits on failure.

`make sml-target-check` tests target artifacts, fixed integer width, canonical
adapter selection and failure-before-output behavior. `make mlworks-host-check`
tests the shared host implementation through the WM-authored I/O probe.

## Validation checkpoint, 2026-10-17

The staged MLton compiler builds and checks the integer fixture, translates a
tiny WM program, and reproduces SML target output byte for byte. Selfcheck,
integer contracts, SML/WM roundtrips and the shared host contract pass.

The generated MLWorks loader also runs on the real PS2. The
`tests/basis/sml_target_probe.sml` fixture receives `["from", "PS2"]` through
the shared host adapter, executes generated Int32 arithmetic and prints
`SML_TARGET_LOADER_OK`. This uses the reusable SML target loader, independently
of the earlier fixed WM host probe.

The existing `tty-ps2-fixed.img` fails the integer-to-real, addition,
subtraction, multiplication and division equality checks in `check-real.sml`;
the ordering check passes. Consequently full compiler
execution on that image is not yet claimed. A previously rebuilt code-generator
object exists separately from the installed object set; integrating it into a
working listener is MLWorks follow-up work. The integer-only target loader
remains usable. Preserve the language's double-precision semantics while
addressing this; no numeric narrowing was made in the target adapters.
The sibling psx-pi-smbshare repository retains the hardware transcripts at
`research/probes/mlworks-target/loader-ps2.log` and
`research/probes/mlworks-target/real-preflight-ps2.log`.
