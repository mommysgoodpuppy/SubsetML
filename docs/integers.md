# Signed 32-bit integers

On 2026-10-17 SubsetML expanded its supported SML subset to include `int`.
The previous real-only restriction is superseded. Restoring this standard SML
type does not introduce syntax or semantics outside SML: SubsetML selects a
fixed precision where SML allows implementation choices.

## Language contract

`int` contains exactly the mathematical integers from **−2,147,483,648** to
**2,147,483,647**. The sign is included in its 32 bits. This is a language
contract, not the precision of the host SML implementation's ordinary `int`.

```sml
val maximum : int = 2147483647
val minimum = ~2147483648
val hexMinimum = ~0x80000000
val add = fn (a : int, b) => a + b
val twice = fn x => x + x             (* int -> int, by defaulting *)
val realTwice = fn (x : real) => x + x (* real -> real *)
val classify = fn 0 => "zero" | _ => "nonzero"
val quotient = ~7 div 3               (* ~3 *)
val remainder = ~7 mod 3              (* 2 *)
```

Decimal and hexadecimal constants are validated before native output. The
negative minimum is a valid literal; `~minimum` is an operation that overflows.
Leading zeros do not change the range. Very long constants are rejected without
first converting them to a host integer. Integer patterns have the same bounds.

`int` admits equality. Lists, records and datatypes containing integers follow
SML's normal equality rules. Integers and reals do not mix implicitly: `1 + 1.0`
is ill-typed, `/` takes reals, and `div`/`mod` take integers. Numeric `+ - * ~ abs`
and ordering use their operand type; unresolved numeric overloads at value
binding closure default to `int`. Existing real equality remains `Real.==` and
`Real.!=`, and real constants are not legal SML patterns.

Arithmetic is checked, not modular. Out-of-range results raise `Overflow`.
Zero divisors raise `Div`. `div` rounds toward negative infinity; a nonzero
`mod` has the divisor's sign. Minimum divided by negative one raises `Overflow`,
but minimum modulo negative one is zero. The mathematical division identity
holds without requiring its intermediate products to fit the integer range.

SubsetML still excludes authored exception declarations, `raise`, and `handle`.
These failures are dynamic exceptions, just as failed matches can already raise
`Match` and `Bind`. Code that requires recoverable integer failures needs a
future checked Basis API; this change does not invent one implicitly.

## Native compilation

Check and lower an explicit dependency-ordered list:

```sh
mkdir -p build/int32
bin/subsetml check program.sml
bin/subsetml native build/int32 program.sml
# Compile the generated SML with the target's normal SML build mechanism.
```

The `native` command emits ordinary full SML, not authored SubsetML. It uses a
fresh helper structure name absent from the input text, typed Int32 constants
and patterns, an initial `type int = Int32.int` alias, and resolved integer operator
implementations. Real operations remain real operations; source functions
shadowing names such as `abs` remain source functions. The native wrapper's
`precision` is `SOME (32 : Int32.int)` so metadata does not leak a host's smaller
integer type. `fmt` remains a source formatter and does not perform this lowering.

Native output uses **`Int32.int` on MLton and MLWorks**, including when MLton's
default integer is configured as 64-bit. On MLWorks this is the boxed signed
32-bit type, not its ordinary immediate signed 30-bit integer. Boxing affects
representation and allocation, not the promised range. The runtime must supply
the `Int32` Basis structure; MLWorks' minimal bootstrap TTY image may need its
Basis object loaded first. The old ordinary-int overflow signal bug does not
justify selecting 30-bit arithmetic for SubsetML.

The first output file establishes the integer type alias for the source list.
Compile the complete generated list in the same order; later files may depend
on that alias and on earlier declarations. Authored type shadowing and `open`
retain ordinary SML lexical behavior.

Files retain their basenames. Duplicate output basenames are rejected. All
input files are checked before output is written. This command takes explicit
source lists, rather than discovering comment imports; use dependency order.
It does not generate MLWorks projects or replace target-specific file/process
adapters. The compiler is built on the desktop with MLton; programs can then be
compiled natively on the PS2 using MLWorks.

## Library and WM scope

The initial bootstrap `Int` namespace supplies:

| Value | Type |
|---|---|
| `toString` | `int -> string` |
| `fromString` | `string -> int option` |
| `precision`, `minInt`, `maxInt` | `int option` |

Parsing/formatting follow the target's SML Int32 Basis implementation, including
SML's `~` sign spelling. As with SML's `fromString`, parsing is not specified to
consume an entire input string. This is a minimal compatibility namespace, not
a complete implementation of the SML Basis `INTEGER` signature.

WM/JS integer support is **deferred**. SubsetML's checker, parser and native
emitter are independent of WM's compiler infrastructure. Its separate WM syntax
reader continues to read existing Number syntax as real; this change does not
reclassify bare WM numbers. Programs using the new integer profile should use
SubsetML source and native output. SML-to-WM translation rejects explicit integer
syntax; integer code is not supported by the WM round-trip execution profile.

Compiler internals, custom Basis sizes/indices, character/scalar codes and
`SubsetNatural` now use signed 32-bit integers; see [the migration notes](integer-migration.md). This language
expansion does not add words, Int64, arbitrary precision, implicit numeric
conversions, integer GPU support, or an independent native machine-code backend.

## Validation

`sh tests/integer.sh` checks range and type errors, then builds/runs generated
native SML with both `-default-type int32` and `-default-type int64`. It exercises
boundaries, integer patterns, equality, nominal payloads, defaulting, shadowed
names, real/integer separation, signed division/modulo, conversion metadata,
catchable runtime failures through a full-SML harness, and a 60,000-step sum.

The separate PS2 primitive probe passed 41 MLWorks Int32 checks before this
implementation; see the sibling psx-pi-smbshare project's
`research/probes/mlworks-int/int32.sml` and its saved transcript. That establishes
the target arithmetic baseline; it does not by itself validate every generated
program or every Int32 parsing/formatting operation.

The generated `integer_basics.sml` was also compiled and loaded in the real PS2
MLWorks listener after `Shell.Project.load "__int32"`. Its full-SML integer
assertion harness passed, including parsing/formatting, precision metadata,
patterns, defaulted arithmetic, overflow, signed division/modulo, shadowing,
and the 60,000-step sum. The separate real-arithmetic assertion was kept in
the desktop test only, since the older PS2 listener's real backend is a
separate porting issue. The transcript is saved in the sibling project's
`research/probes/mlworks-int/subsetml-ps2.log`; the generated program and
harness remain on the PS2 under `/home/ellie/testingstuff/subsetml-int32/`.
