# MLWorks on PS2: host boundary and first program workflow

The [full compiler image workflow](mlworks-batch.md) now runs SubsetML itself
on the PS2 and translates local WM files. The host-probe workflow below is the
earlier bootstrap checkpoint, not the current extent of native support.

Update: compiler indices and the portable Basis now use integers. See
[integer migration](integer-migration.md) for the breaking API changes and
the earlier PS2 compilation-memory limit, now resolved for the full compiler
rebuild by MLWorks' optional low-memory GC policy. The real-index observations
below are historical checkpoints.

For reusable compiler staging and the shared SML target adapter plan, see
[SML targets](sml-targets.md). The probe-specific workflow below remains a
small host-contract test; it is not the general compiler loader.

The package-manager source stays in WM. SubsetML translates it to SML, and
MLWorks compiles and runs that SML on the PS2. The first probe exercises this
path without invoking the WM/JS compiler or its host adapter.

Running the **SubsetML compiler itself** under PS2 MLWorks is a further goal:
it will allow local translation of WM package code. It is not established by
running a translated application. The current staging command runs the
desktop MLton-built SubsetML compiler.

## Host interface

`lib/mlworks/subset_host.sml` now links to the shared full-SML native boundary
in `lib/sml-basis/subset_host.sml`. Its implementation
uses exceptions internally to close streams on failure and translate errors to
`SubsetResult.Err string`. This adds no exception syntax to authored SubsetML
or WM. `exit` terminates the process; it does not return a Result.

| Operation | Arguments | Successful Result payload |
| --- | --- | --- |
| `canonicalPath` | byte path | canonical absolute path |
| `readFile` | byte path | binary contents as a native string |
| `writeFile` | `(contents, path)` | `Void` |
| `writeStdout`, `writeStderr` | binary native string | `Void` |
| `arguments` | `Void` | list of native strings |
| `makeDir`, `removeDir`, `removeFile` | byte path | `Void` |
| `rename` | `(source, destination)` | `Void` |
| `isDir` | byte path | `Bool` |
| `listDir` | byte path | list of entry names, unspecified order |

`makeDir` creates one directory and reports an existing destination as an
error. Directory traversal, recursive creation/removal, permissions, links,
subprocess execution/capture, download and hashing are still to be added as
the pakman port requires them. `writeFile` truncates an existing destination;
it is not an atomic replacement operation. Writes to stdout/stderr flush
before returning. Path arguments reject NUL before opening or changing a
file. Directory listings exclude `.` and `..` explicitly, since this
MLWorks implementation exposes the raw Unix entries. Filesystem races and
host permissions retain normal OS behavior.

`lib/mlworks/checker/subset_host.wm` supplies typed stubs for the translator.
Select the native implementation with `--native-adapter`; those stub bodies
are not an executable filesystem implementation. Their Result type is the
same imported module used by the application. The unrelated JS adapter is
unchanged.

## Stage and check on the desktop

From the SubsetML repository:

```sh
make mlworks-host-check
python3 scripts/stage-mlworks-host.py /tmp/subsetml-mlworks-host
```

The staging script translates `examples/mlworks-host/probe.wm` with explicit
native-adapter selection. It emits the generated SML and MLB, copies the
native adapter, and writes a small MLWorks loader. The desktop test compiles
the generated MLB, preserving private module scopes and native selection.

This loader is specific to the probe's three modules: Result, host, and
application. It is not a general converter from MLB to MLWorks projects.
Only the entry structure is exported by the generated MLB; the application
handles its own Result values before the full-SML driver calls `Probe.main`.

## Run on the PS2

Copy these six staged files into a fresh writable directory on the console:

```text
bootstrap.sml
load.sml
driver.sml
subset_result.sml
subset_host.native.sml
probe.sml
```

Start the existing MLWorks TTY from its `target-objects` directory, with a
timeout and only one compiler process active. For the current installation:

```sh
cd /home/ellie/testingstuff/mlworks-r5900/target-objects
timeout 90 ../run-ps2-tty.sh
```

In the listener, substituting the staging directory as appropriate:

```sml
use "/home/ellie/testingstuff/subsetml-host-20261017/bootstrap.sml";
OS.FileSys.chDir "/home/ellie/testingstuff/subsetml-host-20261017";
use "load.sml";
```

The bootstrap loads `require_all` **once**. Separate `Shell.Project.load`
calls for `__bin_io` and `__byte` reload dependencies and can produce distinct
abstract byte-vector types. A single coherent Basis export preserves sharing
and also makes `List`, `String`, and `CharVector` available to the listener.

The driver constructs all 256 byte values in full SML. The WM-authored probe
creates a directory, writes and reads the bytes, rejects a NUL-containing
path without truncating the original, renames and lists the file, checks a
missing read returns `Err`, and removes its fixture directory. It also checks
canonicalization and argument access, emits all byte values to stdout and
stderr, writes `stream-bytes.bin`, and exits through the host adapter.

The successful run prints `MLWORKS_HOST_PROBE_OK`, framed binary stream data,
and `MLWORKS_HOST_STDERR_OK`, then exits successfully. `stream-bytes.bin`
remains for an independent byte comparison. A listener process returning
zero on EOF alone does not prove success: check the markers, file contents,
and absence of compiler errors too.

The loader calls `Probe.main` explicitly. It does not yet provide a saved
application image, executable delivery, or an application CLI argument
convention distinct from the MLWorks listener's own arguments.

Verified on 2026-10-17 with the existing `tty-ps2-fixed.img` and
`tty-fixed-runtime`: the process exited successfully, both stream frames
contained all 256 bytes exactly, and a separate SSH read of
`stream-bytes.bin` matched bytes 0 through 255. The temporary `probe-dir`
was removed by the program. The transcript is saved in the sibling
psx-pi-smbshare repository at `research/probes/mlworks-host/ps2.log`.
`make mlworks-host-check` also passes using the same native implementation
and generated application on desktop MLton.

## Compiler on the console

The next self-hosting investigation should load the compiler's SML dependency
graph under one coherent Basis, substitute this host adapter and a matching
text adapter, and test parsing/checking/translating a tiny WM file locally.
The compiler currently uses real-valued indices; adding source `int` support
did not migrate those internals. The new SML target staging uses the shared
text adapter and does not need `lib/num.sml`.
Consequently real arithmetic correctness, Basis compatibility, compiler module
loading, and memory use must be verified before calling PS2 compiler support
complete. The console has roughly 27 MiB RAM and no swap in the tested setup.
MLWorks also reserves its extension keyword `require`; the compiler's former
internal `Unify.require` binding is now named `requireKind`.

The pakman port can proceed using desktop translation while that work is
underway. Native WM package translation becomes a required milestone before
claiming the complete package workflow runs entirely on the PS2.
