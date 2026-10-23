# Compiler and Basis integer migration

The active SubsetML compiler source graph now uses signed 32-bit `int` for
source positions, token offsets, type-variable IDs, stamps, arities, recursion
levels, generated names, layout widths and collection counts. Byte codes,
Unicode scalar codes, UTF-16 storage units and codec error offsets use the
same integer type in the portable Basis. Native SML target generation maps
these values and arithmetic operations to `Int32`, including on MLWorks.

This removes real arithmetic from compiler execution. Programs being checked
may still contain real literals, real types and operations: the compiler
stores their spellings and types, rather than evaluating those operations.
`SubsetOrder.compareReal` remains an optional Basis function and is not called
by the compiler. MLWorks' floating-point defect still affects execution of
applications that actually calculate with real values.

## API and algorithm changes

- Collection and source indices/counts accept `int`. Negative values return
  the existing validation errors; fractional/non-finite arguments are type
  errors. The largest representable count is 2147483647. Memory exhaustion
  and checked arithmetic overflow remain runtime failures.
- Text extraction returns `Int32.int list` in the SML adapter. Character
  ordinals originate in the target's ordinary int and are converted explicitly.
  The checker stub declares `int list`; it is replaced at staging time.
- Natural arithmetic and codecs use integer `div`/`mod`; large binary64
  weights and fractional-integrality checks are no longer needed.
- Integer-literal validation compares normalized decimal/hex digit spellings
  against the signed bounds. It can check the minimum and arbitrarily long
  rejected literals without overflowing an accumulator.
- The persistent integer map stores remaining bits in child leaves. It no
  longer doubles a scale that could overflow at the largest valid key.
- Byte and UTF-16 source slicing validate `count <= size - start` after
  validating the start, avoiding overflow in an invalid `start + count`.

The legacy `Num` module and unused `SmlChar` compatibility port are outside
the active compiler graph. Their real-valued interfaces are not changed.

## WM transition

This is a breaking Basis API migration. Since 2026-10-23 `int` translates to
Workman's `I32` ([translation rules](translation.md#integers)), so `make wm`
regenerates the migrated compiler and its `.wm` mirrors run on WM/JS again.

Historical Basis tests that supply real-valued indices or test fractional/NaN
indices require migration. Do not interpret those type failures as a claim
that the old API remains supported. `make sml-target-check` covers the active
native path, compiler rebuilding and new integer Basis contracts. Source SML
format/parse roundtrips remain useful; the roundtrip suite tests WM only with
fixtures in its supported profile.

## PS2 checkpoint

Follow-up: the [batch/object/image workflow](mlworks-batch.md) now runs the full
compiler on the PS2, using emulator-built objects and an image saved on the
console. Native WM-to-SML output matches desktop output, and the generated SML
runs on PS2. A later MLWorks `-gc-low-memory` policy also permits a clean
native rebuild of all 42 reachable compiler units on the console at 17,012 KiB
peak RSS, without swap. The observations below record the earlier loading attempt.

A reduced integer Basis probe passes on the real PS2 under the same listener:
native byte extraction, UTF-8 decoding and persistent map keys including
2147483647 print `SUBSETML_PS2_INTEGER_KERNEL_OK`. This probe does not load the
compiler parser or elaborator. Its source, loader and transcript are saved in
the sibling psx-pi-smbshare repository under
`research/probes/mlworks-integer-compiler/`; the full compiler-load transcript
is saved there separately. No fixed real backend was required for this probe.

The migrated compiler was staged and loaded under the existing MLWorks
listener. It loaded the portable Basis, lexer, parser, types, unifier and
environment, then exhausted memory while compiling the elaborator. The kernel
reported a killed MLWorks process with 21696 KiB anonymous RSS on the 27004 KiB
RAM system with no swap. The console recovered and no compiler process remained.
The compiler did not reach its translation entry point, so complete PS2-hosted
WM translation is not established by this attempt.

The next integration step is a build that does not retain the whole MLWorks
interactive compilation environment: compile staged modules to objects in
bounded batches or on a compatible build host/emulator, then load the program
on PS2, or create a smaller delivered application image. Keep the integer
semantics fixed; the source migration does not solve compiler-build memory use.

Desktop validation includes the checker fixture suite, integer contracts,
staged compiler rebuild/output parity, and independent Python-derived natural
division/formatting vectors, full-range persistent map keys, all 256 native
bytes, Unicode boundaries and overflow-safe slice rejection. See
`tests/index-integers.sh` and `tests/sml-compiler.sh`. `make native-check` passes
the supported desktop native suite, including all 101 checker fixtures and
57 SML source format/parse roundtrips. The wider historical `make test` suite
still contains real-index Basis fixtures and WM compiler regeneration tests;
it is not reported as passing after this API migration.
