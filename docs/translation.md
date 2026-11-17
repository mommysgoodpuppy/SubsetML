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

Declaration forms without a supported WM representation fail explicitly before output is
written. Embedded SML declarations are not part of the WM translation profile. Expression
compatibility forms listed below remain supported.

## Files and modules (spec M1)

| SubsetML | Workman |
|---|---|
| `structure FooBar = struct decs end` in `foo_bar.sml` | the declarations of `foo_bar.wm` |
| other top-level declarations in the same file | more declarations of the same module; `FooBar.x` becomes `x` |
| `open FooBar` (a program structure) | `export from "./foo_bar.wm" import *;` |
| `structure Name = FooBar` at the start of a `struct` (spec M2) | `export from "./foo_bar.wm" import * as Name;` |
| a qualified use `FooBar.x` | `FooBar.x`, plus `from "./foo_bar.wm" import * as FooBar;` at the top |
| comments `(* … *)` | `// …` for one line, `/* … */` for several |

Going back, header namespace imports resolve through the same canonical POSIX file resolver as
SML comment imports. Aliases are resolved before parsing values, types, constructors and record
layouts. The imported module is elaborated once in dependency order; consumers see only their
direct imports plus the initial Basis. A basename is a suggested backend structure name, never a
module identity. Different paths and symlinks to one file share its declarations. Distinct files
with colliding basenames receive distinct structure/output names; Basis structure names are reserved.

The output includes `@subsetml` comment imports using the generated module-to-output mapping.
These use the dependency's actual generated structure name, so the existing entry-file SML
checker can load them without adding structure-alias syntax to SubsetML. Duplicate input files
are emitted once. Cycles and dependencies omitted from the supplied source list are errors.
No output is written until resolution, translation and strict checking all succeed.

This initial reverse-translation profile accepts header `from "./file.wm" import * as Name;`
imports with uppercase aliases and the same local path restrictions as the SML loader. For
compiler round trips, header `export from "./file.wm" import *;` imports lower to ordered SML
`open` declarations, with or without a namespace import of the same module, and SML `open` prints
back as that form. As in SML, the opened bindings become part of the importing module. A namespace
import stays private: it only resolves qualified names, and emits no SML structure binding.
`export from "./file.wm" import * as Name;` lowers to the structure alias of spec restriction M2.
`from "./file.wm" import { a, B as C };` brings names in unqualified. An uppercase name, a type
or constructor, can never be a local binding, so each use is qualified in place (`File.B`, also
in patterns). A value may be shadowed, rebound by a pattern or spelled like a record label, so it
becomes a private `val a = File.a` at the start of the structure instead (see Private
declarations below). Duplicate imported names are
errors. `export from` with a named clause is diagnosed explicitly, as are non-local and later
imports. Namespace values are not first-class.

Workman opens each public Basis module `subset_x.wm` as the namespace `X` in every program, so
`List.filter` is `SubsetList.filter` and `ListPair.zip` is `SubsetListPair.zip`. With `--basis
DIR`, a module that uses an uppercase `X.name` without importing `X` gets `from "basis/x.wm"
import * as X;`. The host adapters and the Basis modules themselves are excluded, and `Int32`
stays the translator's numeric namespace. Without `--basis`, these names keep the bootstrap
meanings below. Workman's `std/` extensions are not part of the Basis and remain unbound.

With `--basis`, bare `Option`, `Some` and `None` use the source datatype in
`subset_option_value.wm`, while `Result`, `Ok` and `Err` use `subset_result.wm`. The translator
supplies private opens when those names occur; it does not define another datatype or rewrite
constructor spellings to a fixed module. Ordinary declarations and explicit imports can shadow
these defaults. Values returned by Basis functions therefore match the same constructors used
in authored patterns. Without `--basis`, host compatibility Option remains available; its
constructor/type definitions now derive from the embedded shared source rather than a second
checker table. Host compatibility and imported source datatypes retain distinct identities.

`before` and `o` are infix in the SML Basis Library, so native output renames bindings with
those names, as it does SML keywords.

A plain `from "./file.wm" import *;` is private in Workman, so it lowers to `local open File in
… end`, which keeps the opened names out of the module's public environment.
Record modules export hygienic field-type aliases for generated reconstruction checks. This
lets an imported record retain fields mentioning private dependencies without requiring its
consumers to import those dependencies or exposing their namespaces.
Alias resolution operates on ordinary WM tokens. Header open imports produce internal
resolved `DOpen` nodes, preserving canonical identity without embedding SML source.

Supply dependency source files together with their consumers when translating. The current
translator discovers program structures from the input files; it does not discover dependencies
from sibling files or existing generated modules. Translating only `src/main.sml` therefore
omits its module imports. For the compiler, use `make wm` to regenerate the complete graph and
stage its host adapters, then `wm check src/main.wm` or
`wm run src/main.wm -- check FILE...` to check or execute it.
Single-entry `check` now follows [explicit comment imports](module-loading-plan.md) with
Workman-aligned canonical identity and private dependency scope. Entry-driven dependency discovery and
backend-generated build artifacts remain later steps; translation still requires the explicit
source list described above.

Current portable library modules (`SmlList`, `SmlListPair`, `SmlOption`, `SmlChar`) are translated and imported just
like other program structures. Their consumers need no host implementation of these functions
and no special translation rule. These are building blocks for the custom SubsetML Basis;
their current SML-shaped APIs are transitional. SubsetML does not support the SML Basis Library
as its standard library. See [basis.md](basis.md).

Named Workman record literals and updates, such as `Token.Token { ..token, marks = marks }`,
are reconstructed from declaration layouts supplied with the input files. An unnamed update,
`.{ ..point, x = 1 }`, takes its layout from the source's inferred type and becomes
`let val u = point val u_x = 1 in {x = u_x, y = #y u} end`; the source's record type must be
fixed within the declaration (annotate the receiver otherwise), and the spread must come first.
Evaluation order and field types are preserved, including overridden
entries. Eligible pure literals retain let-polymorphism, including Result-style carriers and
polymorphic empty lists. Eligible module-level function-record copies and field aliases also preserve generalization.
Other literal shapes and nested or computed copies/aliases still have limitations;
see [carrier lowering](carrier-lowering.md). Backend spelling now uses `BackendNames` before target checking. It resolves lexical value/type
bindings and imported exports, retaining constructor status, source positions and a symbol table
of source/backend names. Unsafe keywords and omitted Basis constructor spellings (including
record constructor `Span`) receive collision-free names. Record labels use a separate consistent
mapping. Same-spelled shadowed bindings resolve independently, while import aliases share the
original declaration's backend spelling. Target primitives without source bindings retain their
existing names. The prefix allocator and collision checks are shared with generated helpers.

Positional WM record constructors are generated from declaration field order, including generic
and first-class constructor values. This is declaration-based lowering; it does not infer a
record name from anonymous fields. Keyword labels such as `open`, `val` and `datatype` remain
ordinary WM labels and go through the shared backend renaming system.

## Declarations

| SubsetML | Workman |
|---|---|
| `val p = e and q = f` | `let p = e and q = f;` |
| `val rec f = fn … and g = fn …` | `let rec f = … and g = …;` |
| `val x : t = e` | `let x: T = e;` |
| `type 'a t = ty` | `type T<a> = Ty;` |
| `type point = {x : real, y : real}` | `record Point = { x: Real64.Real, y: Real64.Real };` |
| `datatype 'a t = A \| B of 'a * real` | `type T<a> = A \| B<a, Real64.Real>;` |
| `datatype t = Only` (one constructor) | `type T = \| Only;` |
| `local dec1 in dec2 end` in a structure | `dec1` with each declaration `private`, then `dec2` |
| `local open X in … end` in a structure | `from "./x.wm" import *;` (a plain, private import) |

Reading Workman, an inline record type, `Point{ a: Int32 }` in an annotation, is a record
declaration just before its statement, as in Workman: the reader hoists `type point = {a : int}`
there and uses `point` in place of the inline form (`Box<t>{ value: t }` becomes `'t box`). A
name already declared, or seen in an earlier inline type, is reused. An inline type inside a
block is hoisted as a private declaration of the module, since SubsetML records are top-level.

### Private declarations

Workman's `private let`, `private type` and `private record` hide a declaration from importers;
SML's `local` does the same, so each translates to the other. Declarations are sequential in
both languages, and a private declaration is visible to the rest of its module, so reading
Workman, a run of private declarations wraps the rest of the structure:

```sml
structure Map = struct
  local
    val rotateLeft = fn …
  in
    val set = fn …
  end
end
```

Named and plain imports read the same way, since they are private in Workman too. A `local`
inside a `let` expression has no Workman counterpart and is an untranslatable declaration.
Restriction L1 (spec §7) matches Workman's rule that a public binding can't mention a private
type.

## Expressions

| SubsetML | Workman |
|---|---|
| `fn x => e`, `fn (x, y) => e`, `fn () => e` | `(x) => { e }`, `(x, y) => { e }`, `() => { e }` |
| `fn a => fn b => e` | `(a) => (b) => { e }` |
| `fn (x : t) => (e : u)` | `(x: T): U => { e }`: a result annotation constrains the body |
| `fn p1 => e1 \| p2 => e2`, or a single rule with a constructor or constant pattern | `match { p1 => { e1 }, p2 => { e2 } }` |
| `case e of …` / `case (a, b) of …` | `match(e) { … }` / `match(a, b) { … }` |
| `if c then a else b` | `if (c) { a } else { b }` |
| `let decs in e1; e2 end` | `{ decs; e1; e2 }` |
| `(e1; e2)` | `(e1; e2)` |
| `f x`, `f (a, b)`, `f ()`, `f x y` | `f(x)`, `f(a, b)`, `f()`, `f(x)(y)` |
| `andalso`, `orelse`, `not e` | conditional branches, `!e` |
| `=`, `<>`, `^` | `==`, `!=`, `++` |
| `Real.== (a, b)`, `Real.!= (a, b)` | `(a: Real64.Real) == b`, `(a: Real64.Real) != b` |
| `Real.==`, `Real.!=` as function values | `(realLeft: Real64.Real, realRight: Real64.Real) => { (realLeft: Real64.Real) == realRight }` (or `!=`) |
| `42.0`, `~42.0`, `1.5e~3` | `42`, `-42`, `1.5e-3` |
| `~ e` | `-e` |
| `Num.String.size`, `Num.List.nth`, etc. | `String.size`, `List.nth`, etc., using the current bootstrap argument order |
| `Num.div`, `Num.mod`, `Num.toString`, `Num.fromString` | `Real64.div`, `Real64.mod`, `Real64.toString`, `Real64.fromString` |
| `x :: xs`, `[a, b]`, `nil` | `[x, ..xs]`, `[a, b]`, `[]` |
| `xs @ ys` | `List.append(xs, ys)` (the SML Basis has no `List.append`, so it reads back as `@`) |
| `()` | `void` |
| `{x = 1.0}` | `.{ x = 1 }` |
| `#x r` (r a variable or a selection) | `r.x` |
| `#x (f a)` | `f(a).x`: a field of a call's result |
| `op +` | `(left, right) => { left + right }`: Workman has no operator values; `op div` is `Int32.div` |
| `(e : t)` | `(e: T)` |
| `#"c"` | `'c'` |

Reading Workman, a backtick string becomes a `^` chain of its text pieces, and each `${ e }` the
text of `e` by its inferred type: `e` itself for a string, `SubsetString.fromChar` for a char,
`SubsetInt32.toString` or `SubsetReal64.toString` for a number (`Int64.toString` for the
MLton-only Int64), and `"true"`/`"false"` for a bool. Number text matches Workman's display:
`-3`, `0.30000000000000004`, `1e+21`. With the SubsetML Basis, a value of another type shows as
`print` shows it (below): `${[1, 2]}` is `[1, 2]`. Types with no display are errors, as is a
`${ x }` whose type nothing decides; annotate it. A number only literals decide takes
Workman's literal default, Int32 or Real64. A backtick string without `${ }` is a plain string
constant.

The reader spells other Workman forms with Basis functions too, so its output passes
`check-portable`: `!e` is `SubsetBool.not e`; `%` is `SubsetInt32.rem` or `SubsetReal64.rem` by
operand type (both truncate toward zero); `==` and `!=` on reals are `SubsetReal64.equal`, IEEE
equality. `print(a, b)` is `SubsetIo.printLine` of the arguments' display, which the translator
writes from their types the way Workman shows them: text and characters as they are, numbers as
above, `void`, `(1, a)`, `[1, 2]`, `{ s = q, x = 1 }`, `Some(2)`, `Ok(x)`, and datatypes as
`End`, `Link(End)`, `Box(1, 2)`, through a recursive helper per datatype. A tuple argument is
several arguments. A type variable nothing decides in a closed value, as in `print(None)`, holds
no value, so its display is never applied; a generic function's own type variable has no display,
so `(x) => { print(x) }` is an error: annotate it. Functions have no display either. The reader treats `print` as Workman's pervasive, so a module binding its own
`print` is an error. Each module these spellings name is imported automatically, under its
structure name, when the form occurs. Real remainder and text are host primitives
(`SubsetRealHost`, adapters in `lib/`); real equality is portable source. `print` writes through
`SubsetHost`, so a native build that prints stages its adapter (`--native-adapter`); the checker
declarations write nothing. Without the SubsetML Basis (`sml` without `--basis`, and round trips)
the reader keeps the SML Basis spellings: `not`, `Int.rem`, `Real.==`, `Int.toString` and SML's
`print` on text.

A carrier group, `Result|a, b, c|`, is desugared as Workman does it: `Result.andThen(a, x =>
Result.andThen(b, y => Result.map(c, z => (x, y, z))))`, through the named namespace's own
`andThen` and `map`, so the SML evaluates and short-circuits in the same order. A one-item group
is the item itself.

`Monad` functions are ordinary record code: `Monad.map(x, Result, f)` reads the `map` field of the
carrier record it is given (`SubsetMonad`, `basis/monad.wm`). A bare namespace in value position
stands for its carrier, so `Result` there is `SubsetResult.carrier`, as in Workman. The reader
marks a bare namespace alias and decides by position: as an expression it is the carrier, while
in a type or pattern it is the plain name (`: String`).

Workman's operator precedences differ from SML's (for example, `==` binds looser than `<`), so
the printer adds parentheses wherever the Workman grammar needs them.

Numeric equality carries a `Real64.Real` annotation because a bare `==` would lose the real type
of a generic SML helper such as `fn (x, y) => Real.== (x, y)`. The reader removes this redundant
annotation when restoring `Real.==` or `Real.!=`. Function values expand to typed lambdas;
these return to equivalent SML lambdas, which the round-trip comparison canonicalizes back
to the primitive function. Unannotated Workman equality is elaborated:
scalar real operands become `Real.==`/`Real.!=`, while SML equality types keep `=`/`<>`.
Modules are checked in dependency order, then checked again with strict SML equality rules
before any output is written. Equality on functions or real-containing lists/records is rejected.
A generic comparison whose numeric type is not determined at its declaration needs a
`Real64.Real` annotation; later calls do not specialize an already generalized comparison.

Standalone module expressions become `val it = ...` in declaration order inside the SML
structure. This follows SML's expression-phrase binding and keeps preceding module values
in scope.

## WM-only function pipes

Reverse translation accepts syntax-based `:>` forms and lowers them immediately
to ordinary SubsetML function applications. SML-to-WM printing still emits calls;
there is no pipe form in the SubsetML language or shared syntax tree.

```wm
value :> stage                 // stage(value)
value :> transform(arg)        // transform(value, arg)
value :> (makeStage(arg))      // makeStage(arg)(value)
value :> makeStage arg         // makeStage(arg)(value)
value :> transform()           // transform(value)
```

An explicit, ungrouped outer call receives the pipe input as its first argument.
A grouped or space-applied stage is evaluated as written, then receives the input.
Only the outermost call's source form determines this rule: `x :> f(a)(b)` is
`f(a)(x, b)`, while `x :> (f(a)(b))` is `f(a)(b)(x)`.
Space application is also accepted in ordinary expressions and for lambda arguments.
Postfix expressions accept type annotations, including call arguments: `add (1: Int32.Int) one`
and `add(1: Int32.Int)(one)` both pass an annotated integer before the second argument.

Pipes associate left-to-right and bind more tightly than unary and binary
operators, matching WM. Thus `1 + 2 :> inc` means `1 + inc(2)`, and
`-2 :> inc` means `-inc(2)`; group the input to pipe a whole arithmetic expression.
Application evaluation order and once-only evaluation follow the lowered call:
the callee (including stage construction) runs before its arguments, which are
evaluated left-to-right. No synthetic variable or duplicated input is needed.

Record member stages (`:> .field`, `:> .method(args)`) lower to ordinary selections and
calls, including nested paths such as `:> .inner.value`. Their receiver must have an
ordinary SML record type established by inference or an annotation; this adds no JS
reflection or nominal record-name guessing. A non-record receiver is an error.
Piped conditionals `flag :> if { yes } else { no }` lower to SML `if`, evaluating the
condition once and only the selected branch.

Bare pipeline lambdas (`=> :> f :> g`, also `let transform ==> :> f`) receive a hygienic
implicit parameter. The block form `=> { :> f; result }` uses the same parameter. A bare
lambda without an initial pipe is nullary. Capture clauses on ordinary lambdas and match
functions are parsed and erased; their capture contract is checked by WM before translation.
The translator checks capture-list syntax and rejects duplicate entries.

This adds no carrier coercion or namespace-as-carrier support.
A named adapter such as `SubsetResult.via(transform)` is an ordinary
function and can be used as a grouped or previously bound stage.

`sh tests/pipes.sh` compares WM/JS and native MLton execution, including curry
forms, precedence, effects, invalid stages and one-way printing.

## Patterns

Workman pins a bare name in a match arm, so it compares against an existing value. A SubsetML
pattern variable in a match arm is therefore written `Var(x)`, except where Workman binds bare
names: constructor arguments, list items and record field puns. `let` and lambda-parameter
patterns bind names normally.

Reverse translation now supports numeric literal and pinned value patterns in matches,
including nested tuples, lists, records and constructor arguments. It resolves constructors
before lowering, evaluates the subject once, and uses branch-local checks with continuations
for fallthrough. Pins capture the outer resolved value before the pattern's binders enter scope.
Integer literals are ordinary SML constant patterns. Real literals use `Real.==`; pinned
comparisons use the existing inferred equality pass. Function pins and non-equality values remain
errors. Real and pinned `let` binding patterns are outside this profile and are diagnosed
explicitly; use a match instead.

Computed patterns `=(expression)` are supported in match arms, including nested constructors,
tuples, lists and records. Their comparisons use inferred equality, so functions remain invalid.
Guards run in source order, only for an attempted branch and after earlier structural checks.
They are evaluated once when reached; a later mismatch does not skip earlier effects. A closure
outside the arm's binders retains outer lexical names without evaluating the expression early.
Cond-style `match { =(condition) => { value }, _ => { fallback } } true` uses the same lowering.

With `sml-entry --basis DIR`, `DIR/subset_process.wm` is the default panic provider when present
and some module in the entry graph spells `Panic`; a graph that never panics doesn't gain the
runtime or its host adapter. `--panic-runtime` overrides it. Source-list translation without a Basis still requires an
explicit provider. Native host adapters remain explicit target choices.

The compiler-only `PPinned` representation does not add syntax to authored SubsetML. It must
be eliminated before target checking. Ordinary SML round trips use the same resolution pass,
so nullary constructor patterns keep their identity without becoming comparisons.

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
| `unit`, `real`, `int` | `Void`, `Real64.Real`, `Int32.Int` |
| `string`, `char`, `bool`, `'a list`, `'a option` | `String`, `Char`, `Bool`, `List<a>`, `Option<a>` |
| type variable `'a` | `a` (Workman type variables are lowercase names) |
| `t1 * t2`, `t1 -> t2` | `(T1, T2)`, `T1 -> T2` |
| `NONE`, `SOME` | `None`, `Some` |

Workman tells constructors from variables by case, so the translation assumes SubsetML follows
the same convention: constructors start uppercase (apart from `true`, `false`, `nil`), and type
constructors and variables start lowercase.

Reading Workman, a name with a leading underscore, `_head`, is `head'`, since SML reserves a
leading `_`. It binds even in a match pattern, as in Workman, where a bare name is pinned. A
module that also writes `head'` itself is rejected rather than merging the two names.

A field selection `user.score` whose receiver nothing else decides takes the one declared record
type that has a `score` field, as Workman resolves it, and is written as a complete record
pattern, `(fn {level = _, score = v} => v) user`, which SML resolves without the receiver's type
name. With no such record, or several, the receiver must be annotated, as in SML.

Lambdas take a bare parameter and an unbraced body as Workman does, `a => b => a + b`; `f => :> g`
is `f` applied to the pipeline lambda `=> :> g`. `Text.of(v)` is a backtick string's `${v}`, and
unapplied it is `v => Text.of(v)`; a generic one, whose type nothing decides, has no display.
An operator nothing decides takes its class default in Workman as in SML (`int` for `+`, `real`
for `/`), so a default carries over unannotated.

## Expression compatibility forms

These expression forms retain their existing translation support; they are separate from
the removed embedded-declaration mechanism.

| Construct | Emitted as |
|---|---|
| `div`, `mod`, `o`, `before` | the SML infix operator, with its operands parenthesized |
| `#lab e` on a non-variable, a bare `#lab` | `#lab(e)`, `#lab` |
| `~` as a value | `~` |

Embedded `val`, `datatype` and `open` declarations are rejected as WM input. SML-to-WM
translation explicitly rejects `val` with explicit type variables, mixed plain/recursive
binding groups, type groups containing records, and opens of non-project structures.
The declaration check also visits nested functions/blocks. It does not split groups or drop
constraints to manufacture a WM translation. Supported source SML checking remains unchanged;
Basis opens already violate the intentional F2 subset restriction.

The native/generated compiler bootstrap needs no embedded declarations. Tests retain SML
format round trips for all checker fixtures; the two acceptance fixtures containing unsupported
WM declaration forms are checked for explicit translation rejection. `tests/no-sml-declarations.sh`
covers rejection without partial output and reserved labels in multiline records/updates.

## Known gaps

- Numeric name mappings assume the current bootstrap adapter namespaces. Shadowing these
  namespaces with program structures is not supported by these syntactic mappings. The mappings
  are provisional and must follow the custom Basis API when that API is defined.

- Identifiers with primes (`ts'`) are emitted unchanged. Workman will support them; frontend-v3
  rejects them for now.
- The translation relies on the coding conventions in [conventions.md](conventions.md): the case
  of names, and not using Workman keywords as identifiers. `subsetml wm` warns about violations.
- A `type` group containing records alongside other bindings has no supported WM translation
  and fails explicitly.
- Existing mappings and unchanged names such as `List.rev` describe the bootstrap compatibility
  layer, not SML Basis Library support. The custom Basis may use different names, argument order
  and Result-based failures. Workman's separate Basis implementation is also transitional and
  should eventually give way to the shared custom library. The compiler now uses the source
  custom Basis and runs in Workman with the staged text and file/process adapters. Compatibility
  names retained in its bootstrap environment are declarations for checked programs, rather
  than additional host requirements.

## Text extraction adapter

The custom text modules use one explicit operation, `SubsetTextHost.codes`. Its checker stub
is an ordinary included module, so generated imports use the normal translation path.
`make wm` replaces the generated stub with `lib/subset_text_host.wm`; native builds use
`lib/subset_text_host.sml`. Shared source performs byte validation, construction and indexing.
Reverse-translation checks use the generated stub before staging the target adapter.

SML `andalso` and `orelse` translate to `if` branches, and Workman's `&&` and `||` translate
back to `andalso` and `orelse`. Both languages evaluate the right operand only when the left
one doesn't decide the result. Round-trip normalization treats the source short-circuit
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
and `make wm` stages `lib/subset_host.wm` plus its local JavaScript adapter. The six CLI operations and
filesystem canonicalization are shared through the source SubsetIo/SubsetProcess wrappers. Reverse translation and
bootstrap checks use the generated declarations before staging either foreign adapter.
The generated CLI accepts arguments through `wm run src/main.wm -- COMMAND ...`.

## Native built-in Panic

For an unshadowed `Panic`, explicitly select the source Basis runtime:

```sh
subsetml sml OUTDIR --panic-runtime path/to/subset_process.wm FILE.wm...
```

The runtime file is included automatically. With `sml`, its dependencies still belong in the
explicit source list; `sml-entry` discovers its closure. Use the existing checker adapters
when translating the Basis, and the native SML adapters when building with MLton. A JS host
adapter is not part of the portable reverse-translation profile.

Shared binding resolution lowers both calls and first-class references to the selected
canonical module's `panic` export. The runtime must provide `panic : string -> 'a`.
Only modules using the built-in gain the implicit private dependency and generated SML import
metadata. Local bindings, parameters, constructors and imported/open values named `Panic`
retain their source identity. Same-basename unrelated modules cannot select a runtime.
Runtime dependency cycles, a missing selection and invalid provider types are explicit errors.
The existing source Basis provider writes the byte-string message and one newline, then exits
unsuccessfully even if stderr writing fails; this lowering adds no host primitive.

## Entry-driven reverse translation

```sh
subsetml sml-entry OUTDIR ENTRY.wm
subsetml sml-entry OUTDIR --panic-runtime path/to/subset_process.wm ENTRY.wm
```

Discovery follows supported header namespace imports relative to each physical importer,
normalizing dot segments before canonicalizing filesystem identities. It reads the entry and
its reachable closure once, including a selected panic runtime's closure, without requiring a
hand-maintained source list. Output directories must already exist. The existing `sml`
source-list command remains available and still requires supplied direct dependencies.

Both commands use the same backend naming, private checking environments, dependency order,
lowering and generated SML metadata. Symlink aliases and diamonds share one module instance;
distinct files with the same basename remain separate. Initialization follows import order.
Missing files and cycles retain importer context and source positions; all discovery and
translation checks finish before output is written. Named, open-only and later imports remain
outside the initial profile; this command does not silently expand their support.

`sml-entry` also emits `project.mlb`, with one basis instance per canonical module. Each module
sees the standard SML Basis and its direct imports; the final build exports the standard Basis
and the entry module only. Shared initialization and nominal identities are preserved. The
explicit source-list command keeps its existing output contract.

Select native implementations explicitly with repeatable adapter options:

```sh
subsetml sml-entry OUTDIR \
  --native-adapter path/to/subset_host.wm lib/subset_host.sml SubsetHost \
  --native-adapter path/to/subset_text_host.wm lib/subset_text_host.sml SubsetTextHost \
  --panic-runtime path/to/subset_process.wm ENTRY.wm
mlton -output program OUTDIR/project.mlb
```

Each option supplies a checker WM module, native SML file and exported structure identifier.
Selection uses the checker's canonical filesystem identity, including symlinks; it never
matches a basename. The checker must be reachable from the entry/runtime roots and can have
only one selected adapter; `--native-adapter-if-used` takes the same arguments but skips a
checker the program doesn't reach, for a driver that stages every host adapter whatever the
program imports (`wm sml`). Generated checker SML remains intact. The MLB instead loads the
native implementation privately and exports it under the graph's allocated backend name.
Native paths are canonical and quoted in the build file.

The native file receives the standard Basis and the checker's direct imports under their
source namespace aliases. Each alias is constructed in a separate basis scope, so aliases
cannot accidentally shadow another dependency's backend name. Implementation structures and
private dependencies do not leak. Native export/import names must be valid SML structure
identifiers; invalid names and missing/duplicate/unreachable selections fail before writing.
The adapter implements the checker interface; the lowerer does not parse or rewrite opaque
native SML, and MLton checks its implementation when compiling the generated build.
JS/FFI adapter sources remain outside reverse translation: use source-generated checker WM
in the native staging graph. The lexer smoke probe now builds through this selection mechanism,
without copying native files over generated output. Complete lexer parity remains pending.


Filesystem stems now pass through `BackendNames.moduleHint` before canonical module-name
allocation. Separators become word boundaries, and empty/digit-leading hints receive a safe
prefix. Spelling collisions still allocate distinct backend names and never merge canonical
modules. `tests/wm-entry.sh` compiles hyphen/underscore collisions, digit-leading and punctuation-only
filenames through the generated MLB.


## Native signed 32-bit integers

`bin/subsetml native OUTDIR FILE.sml...` checks an explicit source list in
declaration order and emits native SML using `Int32.int`. Output directories
must already exist; files keep their basenames, and duplicate output names
are rejected. All files are validated before any output is written. See
[the integer contract](integers.md) for native runtime and scope details.

This is distinct from `fmt`, which preserves source spelling, and from
`sml`/`sml-entry`, which translate WM syntax to checked SubsetML source. The
native pass does not require the WM compiler, Deno or JavaScript. WM integer
code translates as described in [Integers](#integers).

## Integers

SML `int` and Workman `Int32.Int` have the same range, checked arithmetic and `div`/`mod`
rounding. A Workman integer literal takes its type from context and otherwise defaults to
`Int32.Int`, as an SML integer constant is `int`. Workman's default for an operation with no
literal is `Real64.Real`, unlike SML's `int`:

| SML | Workman |
|---|---|
| `int` | `Int32.Int` |
| `42`, `~5`, `0x7f` (expression or pattern) | `42`, `-5`, `0x7f` |
| `~ 5` (negation applied to a constant) | `-(5)` |
| `a div b`, `a mod b`, `div` | `Int32.div(a, b)`, `Int32.mod(a, b)`, `Int32.div` |
| `Int.rem (a, b)` | `a % b`: both truncate toward zero, so the remainder has the dividend's sign |
| `42.0` | `42.0` |
| `Int64.int`, `Word8.word`–`Word64.word`, `Real32.real` | `Int64.Int`, `Word8.Word`–`Word64.Word`, `Real32.Real` |
| `0w7`, `0wx1F` | `7`, `0x1F`: a Workman literal takes the word type from context |
| `a div b` on a word or `Int64.int` | `Word16.div(a, b)`, `Int64.div(a, b)`: the type the file's elaboration resolved |

An int constant prints as a bare literal, which Workman types as `Int32.Int` wherever SML has
`int`, and every real keeps its fraction, so `SML → Workman → SML` is unchanged. Reading
hand-written Workman, a bare integer literal takes its type from context
during translation, as in Workman: in a `Real64.Real` context, `0` and `-1` become `0.0` and
`~1.0`; in a word context, `7` becomes `0w7`. Undecided, it is `int`, which matches Workman's
`Int32.Int` default. A literal outside the `Int32.Int` range is `Int64.int` or a word by context
and `real` otherwise; `1.0` and `1e3` are `real` or `Real32.real` by context. `(n: Int32.Int)` is still read as an int
constant. A numeric operation that no literal decides, such as `fn (a, b) => a + b`, would default
to `int` in SML but `Real64.Real` in Workman, so it is rejected in both directions; annotate an
operand as `int` or `real`. `Int.*` and `abs` have no Workman mapping yet.
