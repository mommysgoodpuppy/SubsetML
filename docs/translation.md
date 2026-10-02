# SubsetML ⇄ Workman translation

`subsetml wm OUTDIR FILE.sml...` translates SubsetML to Workman, and `subsetml sml OUTDIR
FILE.wm...` translates back. Both directions go through the same syntax tree (`src/syntax.sml`):

```
SML text --Parser--> Syntax --WmPrint--> Workman text
SML text <-SmlPrint-- Syntax <--WmParse-- Workman text
```

The Workman spelling is frontend-v3's (`../wm-mini/tooling/frontend-v3/lexical-design.md`).

**The round-trip rule:** for every file, `SML → Workman → SML` gives back the same declarations,
up to the canonical forms in `src/normalize.sml`. `make test` checks this for the
implementation and the accept tests. `make bootstrap-check` goes further: it translates the
whole implementation to Workman and back, then builds and runs the regenerated compiler.

When a construct has no clear Workman form, the SML is emitted unchanged (see the fallbacks
below), and WmParse reads it back.

## Files and modules (spec M1)

| SubsetML | Workman |
|---|---|
| `structure FooBar = struct decs end` in `foo_bar.sml` | the declarations of `foo_bar.wm` |
| other top-level declarations in the same file | more declarations of the same module; `FooBar.x` becomes `x` |
| `open FooBar` (a program structure) | `from "./foo_bar.wm" import *;` |
| a qualified use `FooBar.x` | `FooBar.x`, plus `from "./foo_bar.wm" import * as FooBar;` at the top |
| comments `(* … *)` | `// …` for one line, `/* … */` for several |

Going back, a Workman module becomes a structure named after its file, and namespace imports are
dropped (SML names structures without importing them).

Current portable library modules (`SmlList`, `SmlListPair`, `SmlOption`, `SmlChar`) are translated and imported just
like other program structures. Their consumers need no host implementation of these functions
and no special translation rule. These are building blocks for the custom SubsetML Basis;
their current SML-shaped APIs are transitional. SubsetML does not support the SML Basis Library
as its standard library. See [basis.md](basis.md).

## Declarations

| SubsetML | Workman |
|---|---|
| `val p = e and q = f` | `let p = e and q = f;` |
| `val rec f = fn … and g = fn …` | `let rec f = … and g = …;` |
| `val x : t = e` | `let x: T = e;` |
| `type 'a t = ty` | `type T<a> = Ty;` |
| `type point = {x : real, y : real}` | `record Point = { x: Number, y: Number };` |
| `datatype 'a t = A \| B of 'a * real` | `type T<a> = A \| B<a, Number>;` |
| `datatype t = Only` (one constructor) | `type T = \| Only;` |

## Expressions

| SubsetML | Workman |
|---|---|
| `fn x => e`, `fn (x, y) => e`, `fn () => e` | `(x) => { e }`, `(x, y) => { e }`, `() => { e }` |
| `fn a => fn b => e` | `(a) => (b) => { e }` |
| `fn p1 => e1 \| p2 => e2`, or a single rule with a constructor or constant pattern | `match { p1 => { e1 }, p2 => { e2 } }` |
| `case e of …` / `case (a, b) of …` | `match(e) { … }` / `match(a, b) { … }` |
| `if c then a else b` | `if (c) { a } else { b }` |
| `let decs in e1; e2 end` | `{ decs; e1; e2 }` |
| `(e1; e2)` | `(e1; e2)` |
| `f x`, `f (a, b)`, `f ()`, `f x y` | `f(x)`, `f(a, b)`, `f()`, `f(x)(y)` |
| `andalso`, `orelse`, `not e` | conditional branches, `!e` |
| `=`, `<>`, `^` | `==`, `!=`, `++` |
| `Real.== (a, b)`, `Real.!= (a, b)` | `(a: Number) == b`, `(a: Number) != b` |
| `Real.==`, `Real.!=` as function values | `(realLeft: Number, realRight: Number) => { (realLeft: Number) == realRight }` (or `!=`) |
| `42.0`, `~42.0`, `1.5e~3` | `42`, `-42`, `1.5e-3` |
| `~ e` | `-e` |
| `Num.String.size`, `Num.List.nth`, etc. | `String.size`, `List.nth`, etc., using the current bootstrap argument order |
| `Num.div`, `Num.mod`, `Num.toString`, `Num.fromString` | `Number.div`, `Number.mod`, `Number.toString`, `Number.fromString` |
| `x :: xs`, `[a, b]`, `nil` | `[x, ..xs]`, `[a, b]`, `[]` |
| `xs @ ys` | `List.append(xs, ys)` (the SML Basis has no `List.append`, so it reads back as `@`) |
| `()` | `void` |
| `{x = 1.0}` | `.{ x = 1 }` |
| `#x r` (r a variable or a selection) | `r.x` |
| `(e : t)` | `(e: T)` |
| `#"c"` | `'c'` |

Workman's operator precedences differ from SML's (for example, `==` binds looser than `<`), so
the printer adds parentheses wherever the Workman grammar needs them.

Numeric equality carries a `Number` annotation because a bare `==` would lose the real type
of a generic SML helper such as `fn (x, y) => Real.== (x, y)`. The reader removes this redundant
annotation when restoring `Real.==` or `Real.!=`. Function values expand to typed lambdas;
these return to equivalent SML lambdas, which the round-trip comparison canonicalizes back
to the primitive function. Unannotated Workman equality is elaborated:
scalar real operands become `Real.==`/`Real.!=`, while SML equality types keep `=`/`<>`.
Modules are checked in dependency order, then checked again with strict SML equality rules
before any output is written. Equality on functions or real-containing lists/records is rejected.
A generic comparison whose numeric type is not determined at its declaration needs a
`Number` annotation; later calls do not specialize an already generalized comparison.

Standalone module expressions become `val it = ...` in declaration order inside the SML
structure. This follows SML's expression-phrase binding and keeps preceding module values
in scope.

## Patterns

Workman pins a bare name in a match arm, so it compares against an existing value. A SubsetML
pattern variable in a match arm is therefore written `Var(x)`, except where Workman binds bare
names: constructor arguments, list items and record field puns. `let` and lambda-parameter
patterns bind names normally.

| SubsetML | Workman |
|---|---|
| `case e of x => …` | `match(e) { Var(x) => … }` |
| `SOME x`, `Node (l, x, r)` | `Some(x)`, `Node(l, x, r)` |
| `(a, b)` in a match arm | `(Var(a), Var(b))` |
| `x :: rest` | `[x, ..rest]` |
| `{x, y = q}` | `.{ x, y = Var(q) }` |
| `p : t` | `(p: T)` |

## Names and types

| SubsetML | Workman |
|---|---|
| type constructors `token`, `Syntax.pos` | `Token`, `Syntax.Pos` |
| `unit`, `real` | `Void`, `Number` |
| `string`, `char`, `bool`, `'a list`, `'a option` | `String`, `Char`, `Bool`, `List<a>`, `Option<a>` |
| type variable `'a` | `a` (Workman type variables are lowercase names) |
| `t1 * t2`, `t1 -> t2` | `(T1, T2)`, `T1 -> T2` |
| `NONE`, `SOME` | `None`, `Some` |

Workman tells constructors from variables by case, so the translation assumes SubsetML follows
the same convention: constructors start uppercase (apart from `true`, `false`, `nil`), and type
constructors and variables start lowercase.

## SML fallbacks

These have no clear Workman form and are emitted as SML. WmParse reads them back.

| Construct | Emitted as |
|---|---|
| `div`, `mod`, `o`, `before` | the SML infix operator, with its operands parenthesized |
| `#lab e` on a non-variable, a bare `#lab` | `#lab(e)`, `#lab` |
| `~` as a value | `~` |
| `val` with explicit type variables, `val … and rec …` | the SML declaration plus `;` |
| `open` of a Basis structure | the SML declaration plus `;` |

## Known gaps

- Numeric name mappings assume the current bootstrap adapter namespaces. Shadowing these
  namespaces with program structures is not supported by these syntactic mappings. The mappings
  are provisional and must follow the custom Basis API when that API is defined.

- Identifiers with primes (`ts'`) are emitted unchanged. Workman will support them; frontend-v3
  rejects them for now.
- The translation relies on the coding conventions in [conventions.md](conventions.md): the case
  of names, and not using Workman keywords as identifiers. `subsetml wm` warns about violations.
- A `type` group mixing record and non-record bindings falls back to SML, which WmParse cannot
  read yet.
- Existing mappings and unchanged names such as `List.rev` describe the bootstrap compatibility
  layer, not SML Basis Library support. The custom Basis may use different names, argument order
  and Result-based failures. Workman's separate Basis implementation is also transitional and
  should eventually give way to the shared custom library. The compiler now uses the source
  custom Basis and runs in Workman with the staged text and file/process adapters. Compatibility
  names retained in its bootstrap environment are declarations for checked programs, rather
  than additional host requirements.
- Positions inside an SML fallback declaration are relative to the fallback, so comments next
  to it may move when translating back.

## Text extraction adapter

The custom text modules use one explicit operation, `SubsetTextHost.codes`. Its checker stub
is an ordinary included module, so generated imports use the normal translation path.
`make wm` replaces the generated stub with `lib/subset_text_host.wm`; native builds use
`lib/subset_text_host.sml`. Shared source performs byte validation, construction and indexing.
Reverse-translation checks use the generated stub before staging the target adapter.

SML `andalso` and `orelse` translate to `if` branches: Workman's `&&` and `||` are
eager operators. In the reverse direction, those eager operators become a case on both
operands, preserving their evaluation. Round-trip normalization treats the source short-circuit
forms and their conditional expansions as equivalent.

The Workman printer's own text operations use the portable byte layer. One-character strings
come from `CompilerText.str` and its source literal table, not a host `String.str` mapping.
Names and numeric literal spelling are processed as byte lists. Its hexadecimal helper checks
a byte code, splits it with at most fifteen subtractions and selects source digit literals;
`Num.div`/`Num.mod` are unnecessary. `tests/wm-printer.sh` checks all 256 character spellings,
a combined byte string, lexer decoding, names, numeric spelling, comments and formatting with
original SML, round-tripped SML and generated Workman. Bootstrap name mappings remain available
for other callers during migration; they are separate from the printer's own dependencies.

Text ordering uses explicit custom Basis comparisons. SubsetML rejects string and character
operands to `<`, `>`, `<=`, and `>=`; numeric ordering translates directly to Workman.
The source byte comparator orders unsigned codes and does not depend on target string ordering.

The CLI host adapter follows the same staging rule: `src/subset_host.sml` provides typed
checker/round-trip declarations; native builds select `lib/subset_host.sml` after SubsetResult,
and `make wm` stages `lib/subset_host.wm` plus its local JavaScript adapter. The six operations
are shared through the source SubsetIo/SubsetProcess wrappers. Reverse translation and
bootstrap checks use the generated declarations before staging either foreign adapter.
The generated CLI accepts arguments through `wm run src/main.wm -- COMMAND ...`.
