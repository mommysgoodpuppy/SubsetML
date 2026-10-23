# MLWorks batch/object bootstrap on PS2

The full compiler now runs on the PS2 as a saved image: it translates local
WM source, checks valid SML and rejects invalid SML. Its large compilation
units were built with the R5900 emulator on the workstation; the objects were
loaded and the compiler image saved on the real PS2. A later MLWorks
`-gc-low-memory` policy now also permits a **clean native rebuild of all 42
reachable compiler units** on the PS2, at 17,012 KiB peak RSS without swap.
Details follow the small bootstrap experiment below.

The small SubsetML integer graph has been compiled to native `.mo` files by
the PS2 batch compiler, loaded in a fresh listener, and saved as an application
image whose cold start runs the test without starting a listener. This tests
the build/run separation needed to avoid compiling the whole SubsetML compiler
inside an interactive environment. It does not yet build the full compiler.

## Memory limits

The MLWorks investigation found and fixed an independent GC planning bug:
with a sufficiently low advisory limit, it repeatedly scheduled newly created
empty generations until exhausting arena spaces. The patched runtime passes
the previously failing `-limit 4` translation on the real PS2. It is installed
separately for testing; the normal launcher still uses the existing runtime.
See the sibling MLWorks repository's
[`PS2-GC-INVESTIGATION.md`](../../mlworks/PS2-GC-INVESTIGATION.md) for the cause,
regression test and compilation measurements. That fix alone did not resolve
the larger compilation peak. The subsequent explicit `-gc-low-memory` policy
does: a clean on-console build of all 42 reachable SubsetML units now passes,
peaking at 17,012 KiB total RSS. The policy uses smaller generations and
pressure-triggered collections with growth headroom; the default policy is
unchanged. The runtime and staged native build are installed separately under
`/home/ellie/testingstuff/mlworks-low-memory`. See the investigation document
for the exact command and experimental process-limit overrides.

MLWorks' `-limit` controls its advisory managed heap target and can increase.
The Linux `RLIMIT_DATA` limit (`ulimit -d`) is a separate OS-enforced cap on
data allocations, including the writable anonymous mappings used by this
runtime. It does not count all process memory: stacks, shared libraries and
other mappings are outside that limit. It is not a hard RSS ceiling.

Use `sh tools/scripts/run-memory-limited.sh COMMAND...` from the sibling
MLWorks repository, invoking the runtime directly or through an exec-only
launcher. Its defaults are now a 12288 KiB OS data limit, a sampled 16384 KiB
RSS watchdog, a 4096 KiB available-memory reserve, and a 90-second timeout.
Override with `MLWORKS_DATA_LIMIT_KB`, `MLWORKS_RSS_LIMIT_KB`,
`MLWORKS_RESERVE_KB` and `MLWORKS_TIMEOUT_SECONDS`. It samples `/proc` about
once per 100 ms and kills the tracked runtime on a threshold or timeout.
This is not a hard RSS guarantee: an allocation burst can outrun sampling.
The limits apply only to the launched process. No kernel/global changes.

The original wrapper used a 16384 KiB data limit without an RSS watchdog.
That protected the small allocation test, but a larger WM-parser compilation
still reached 21464 KiB anonymous RSS and was killed by the kernel. The lower
cap and watchdog are a response to that observed gap, not proof that the
original data limit bounded the entire process.

Do not use a small virtual-address limit (`ulimit -v`) for MLWorks: its arena
reserves considerably more address space than it commits. The old 24 MiB
address-space experiment failed at startup, before doing useful work.
The data limit allows that reservation while bounding writable allocation.

## Clean native rebuild with the low-memory runtime

The later experiment at
`/home/ellie/testingstuff/mlworks-low-memory/full-native` starts with an empty
object directory and builds all 42 reachable compiler units using
`-gc-low-memory -limit 6`. It uses the existing MLWorks batch image and Basis
objects as bootstrap tools. Peak total RSS is 17,012 KiB, with no swap; after
exit the PS2 has 20,792 KiB available. The runtime option, exact build command
and process-limit overrides are documented in the sibling MLWorks
[GC investigation](../../mlworks/PS2-GC-INVESTIGATION.md).

The new native objects were loaded on the PS2 and saved as
`/home/ellie/testingstuff/mlworks-low-memory/full-native/subsetml.img`.
The image is 10,373,312 bytes, SHA-256
`4331cb2bdf7de0c2659c8f00e7b4cba26a70df2e152128c7bc4e020fef9b6c0c`.
It translates local WM to the expected SML, accepts the existing valid SML
fixture and rejects the out-of-range integer fixture with exit status 1.
The ordinary launcher still points to the earlier image/runtime; this
experimental installation is separate. Full native build, image save, run
and memory logs are under `research/probes/mlworks-gc/` in psx-pi-smbshare.
The generated SML also ran successfully on the PS2. A subsequent primitive
Int32 probe passed all 41 checks with the new GC policy enabled.

## Earlier allocation-limit probe

On the real PS2, startup succeeds at a 16 MiB data limit. A deliberately
oversized allocation (`CharVector.tabulate (12000000, ...)`) then produced:

```text
Warning: Live data exceeds advisory limit of 12Mb. Temporarily increasing limit to 25Mb.
Unable to obtain virtual memory (16Mb used, 1024Kb requested)
Fatal error in runtime system: Out of virtual memory.
```

The runtime exited with failure instead of growing until the kernel killed it.
This is expected limit enforcement, not a recoverable SubsetML Result error.

## Reproduce the small batch build

From the SubsetML desktop checkout:

```sh
python3 scripts/stage-mlworks-batch-probe.py /tmp/subsetml-batch-small
```

Copy the output to `/home/ellie/testingstuff/subsetml-batch-small` on PS2.
The helper emits a specific four-unit project: integer prelude, SubsetResult,
SubsetList and a full-SML test entry point. The portable modules are emitted
by `sml-target`, with MLWorks `require` declarations added for batch compilation.
All four units are listed in the project; listing only the entry is insufficient.
The target Basis object directory defaults to the current PS2 installation;
override `--library-path` for a different installation.

The startup `bootstrap.sml` and `load.sml` left by source target staging are
not used in this experiment. The project and `.mo` objects are the build path.

With the limit wrapper copied into the probe directory, run on the PS2:

```sh
cd /home/ellie/testingstuff/subsetml-batch-small
export MLWORKS_PERVASIVE=/home/ellie/testingstuff/mlworks-r5900/pervasive-target
export LD_LIBRARY_PATH=/home/ellie/testingstuff/mlworks-r5900/tty-fixed-runtime
sh run-memory-limited.sh \
  /home/ellie/testingstuff/mlworks-r5900/tty-fixed-runtime/main \
  -MLWpass MLWargs -limit 8 \
  -load /home/ellie/testingstuff/mlworks-r5900/batch-ps2-native.img \
  MLWargs -pervasive-dir "$MLWORKS_PERVASIVE" \
  -project batch-probe.mlp -verbose -build
```

The build exits successfully and writes `objects/Release/{prelude,subset_result,
subset_list,batch_probe}.mo`. It reports about a 5 MiB managed heap during the
build. A recovered project dependency-analysis limitation prints
`Cannot find structure Int32 during dependency analysis of unit prelude`,
despite the explicit `require "__int32"`, successful compilation and working
objects. This diagnostic still needs investigation; do not equate a zero
status or object existence alone with semantic success.

## Load objects and save an image

Create a fresh `run-objects` directory containing symlinks to the target Basis
`.mo` files and the four newly compiled `.mo` files. The latter take precedence.
Start the limited listener from that directory and evaluate:

```sml
Shell.Project.load "batch_probe";
BatchProbe.run ();
MLWorks.Internal.save
  ("/home/ellie/testingstuff/subsetml-batch-small/probe.img", BatchProbe.run);
```

`BatchProbe.run` checks integer-backed list length and checked indexing, then
prints `SUBSETML_BATCH_OBJECT_OK`. The save operation returns a restart
function in the build process; the image retains the supplied entry closure.
Its save-time GC reported approximately 1.4 MiB resident ML values, which is
not the process's total RSS. This uses the working internal image mechanism;
standalone ELF executable delivery is not established here.

Restart with the same runtime and no listener image:

```sh
export MLWORKS_DATA_LIMIT_KB=8192
sh run-memory-limited.sh \
  /home/ellie/testingstuff/mlworks-r5900/tty-fixed-runtime/main \
  -MLWpass MLWargs -limit 4 -load probe.img MLWargs
```

## Small-graph validation

Verified on 2026-10-17: the cold application image printed the success marker
and exited with status zero at both 16 MiB and 8 MiB OS data limits. The saved
image is 5532540 bytes. Hardware logs, the limit-allocation test and source
project are retained in the sibling psx-pi-smbshare repository under
`research/probes/mlworks-batch/`. The small probe required no swap, and available
memory returned to approximately 20 MiB after it exited.

## Full compiler staging and build

```sh
python3 scripts/stage-mlworks-batch-compiler.py /tmp/subsetml-batch-compiler
```

This invokes the existing SML target generator for the compiler graph, adds
MLWorks build directives from explicit source dependencies, emits a flat
`compiler.mlp`, and removes only the generated final `Main.main ()` invocation.
The entry point remains available for saving an image. All units use the same
`require_all` Basis identity; portable modules then import the Int32 prelude.
The helper also stages the memory wrapper and `run-subsetml.sh`. Use
`--memory-wrapper` if the sibling MLWorks checkout is in a different location.
The helper performs no remote actions.

The first console build compiled 32 objects before hitting the 16 MiB data
limit while compiling `wm_parse`. A fresh batch process reused those objects,
but `wm_parse` still exceeded physical memory during compilation. The kernel
reported 21464 KiB anonymous RSS despite that data limit. This led to the
revised lower allocation limit and sampled RSS/reserve watchdog described
above. No further large console build is claimed safe solely because of a
data limit.

The existing R5900-capable QEMU source was built on the workstation with:

```sh
/home/ellie/git/psx-pi-smbshare/research/frno7-qemu/configure \
  --target-list=mipsel-linux-user --disable-linux-io-uring \
  --disable-werror --disable-docs --disable-tools
make -j4
```

Use a separate build directory. The ordinary installed QEMU does not expose
the required R5900 CPU. The tested binary is
`/home/ellie/ps2linux/build/work/qemu-r5900-subsetml/mipsel-linux-user/qemu-mipsel`.
The bootstrap runtime, batch image, pervasive objects and Basis objects were
copied from the PS2 into `/tmp/subsetml-batch-host`. Its `sysroot/lib` contains
the toolchain's musl libc as `ld-musl-mipsel-sf.so.1`.

Stage a project with that host-side Basis object path:

```sh
python3 scripts/stage-mlworks-batch-compiler.py /tmp/subsetml-batch-emulated \
  --library-path /tmp/subsetml-batch-host/target-objects
cd /tmp/subsetml-batch-emulated
timeout 180 /home/ellie/ps2linux/build/work/qemu-r5900-subsetml/mipsel-linux-user/qemu-mipsel \
  -cpu R5900 -L /tmp/subsetml-batch-host/sysroot \
  -E LD_LIBRARY_PATH=/tmp/subsetml-batch-host/tty-fixed-runtime \
  /tmp/subsetml-batch-host/tty-fixed-runtime/main \
  -MLWpass MLWargs -limit 48 \
  -load /tmp/subsetml-batch-host/batch-ps2-native.img \
  MLWargs -pervasive-dir /tmp/subsetml-batch-host/pervasive-target \
  -project compiler.mlp -verbose -build
```

This completed the reachable graph: 42 `.mo` files, approximately 1.7 MiB in
total. Unused source units listed in the project need not be built. The
recovered library dependency-analysis diagnostics remain, but typechecking,
object compilation and hardware execution succeeded.

## Save and run the full compiler on PS2

Copy the objects to `emulated-objects` in the staged console directory. Make
a `run-objects` overlay with symlinks to the existing target Basis `.mo` files
and these new objects, with the new objects taking precedence. Start the
limited listener there and evaluate:

```sml
Shell.Project.load "main";
MLWorks.Internal.save
  ("/home/ellie/testingstuff/subsetml-batch-compiler/subsetml.img",
   fn () => ignore (Main.main ()));
```

This loaded and saved successfully under the revised wrapper. Save-time GC
reported approximately 2.6 MiB live ML values; this is not total process RSS.
Run the saved image using the staged launcher:

```sh
cd /home/ellie/testingstuff/subsetml-batch-compiler
sh run-subsetml.sh check check.sml
sh run-subsetml.sh sml native-out tiny.wm
```

The launcher uses an 8 MiB advisory heap target plus the allocation/RSS/reserve
wrapper. Keep that startup target: at 4 MiB the tiny translation hit the
runtime's `Run out of arena spaces` failure; at 8 MiB it succeeded. The
precise low-target GC defect is not diagnosed. The advisory target may still
increase; the wrapper remains the separate allocation/memory safeguard.

Verified on the real PS2 on 2026-10-17:

- A locally read WM identity/string program translated to SML with exit zero.
- That output matched desktop SubsetML output byte for byte.
- MLWorks loaded the resulting SML and evaluated its result to `"PS2"`.
- Checking a file containing `2147483647` and `1.25` succeeded. Real literals
  are parsed/typechecked, not evaluated by the compiler.
- `2147483648` was rejected at line 1, column 15 with failure status 1.

The compiler image is 10282096 bytes, with SHA-256
`42ef39ce165fd3015e41d1edaaf954eddb9ceb1355e846a1f4a90cc166988d2f`.
The existing runtime is still required to load it; this is not a standalone
ELF executable. Full-build, limit-failure, image-save, translation, checking
and generated-program transcripts and the 42 object hashes are saved under
`research/probes/mlworks-batch/` in the sibling psx-pi-smbshare repository.
After the final launcher check, the console had 20496 KiB available memory
and no surviving compiler process.

This initial run established the native compiler execution and generate/run
milestone with an emulator-assisted build. The subsequent `-gc-low-memory`
experiment also establishes a clean on-console compiler rebuild (see above).
Arbitrary package compatibility and execution of real arithmetic in generated
applications remain separate work.
