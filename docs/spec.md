# SubsetML Specification

Status: draft 0.2 (2026-10-02).

## 1. Principle

SubsetML's language is Standard ML as given by *The Definition of Standard ML (Revised)*
(1997), with parts removed. Its syntax and language semantics make no additions or changes.
This document specifies the language. The separately specified
[SubsetML Basis](basis.md) defines the portable library; its APIs are not language features.

> **Language conformance rule.** Given the same supplied library environment, every phrase
> SubsetML accepts is a phrase of Standard ML, with the static and dynamic semantics the
> Definition gives it. Differences in language support may only reject phrases, never change
> the meaning of an accepted language construct.

A SubsetML program can be compiled by an SML'97 compiler such as MLton with the same
library environment and appropriate target primitives supplied. The conformance rule does
not assume any particular library, including the SML Basis Library. Current tests use the
bootstrap environment to verify the language implementation.

Where the Definition leaves a choice to the implementation (file inclusion, the context that
resolves overloading and flexible records, integer precision), SubsetML may pin that choice down.
Those choices are listed in §10.

The section and figure numbers below refer to the Definition. Its LaTeX source is in
`../wm-mini/research/The-Definition-of-Standard-ML-Revised` (`syncor.tex`, `synmod.tex`,
`app1.tex` for derived forms, `app3.tex`/`app4.tex` for the initial basis, `overloading.tex` for
Appendix E).

### Why these omissions

SubsetML has three jobs. It is the common language of Workman (`../wm-mini`) and SML. It is the
route for compiling Workman through MLton. And it is a target simple enough for a small native
compiler. The omissions follow the Workman ledger (`../wm-mini/docs/smlparallels.md`, "SML
Language Forms With No Workman Equivalent"). Workman's *differences*, such as nominal records,
pinned match identifiers, `Number` and Workman-only syntax, are not part of SubsetML. Where SML
and Workman disagree, SubsetML keeps SML's meaning, sometimes restricted so that both agree.

## 2. Lexical structure (§2)

### 2.1 Reserved words

SubsetML reserves every reserved word of the Core and the Modules (§2.1, §3.1), including the ones
for omitted features. Those can never be used as identifiers, and an implementation reports them
as unsupported features.

Reserved words SubsetML uses:

```
and andalso case datatype else end fn if in let of open orelse rec
struct structure then type val
( ) [ ] { } , : ; _ | = => -> #
```

Reserved words for omitted features:

```
abstype as do eqtype exception fun functor handle include infix infixr local
nonfix op raise sharing sig signature where while with withtype :> ...
```

### 2.2 Special constants

| Constant | Status |
|---|---|
| integer, decimal and hex (`42`, `~7`, `0x1F`, `~0x1f`) | **omitted** with `int` (§9.3); write `42.0` |
| real (`1.5`, `~2.0e~3`, `1E10`) | kept |
| string (all escapes of §2.2, including `\^c`, `\ddd`, `\uxxxx` and `\f…f\` gaps) | kept |
| character `#"c"` | kept |
| word (`0w7`, `0wx1F`) | **omitted** |

A string may contain only the printable characters of §2.2 (codes 33–126 and space) besides
escapes. The character set is 8-bit, so `\uxxxx` must denote a value ≤ 255 (Appendix E: a
constant must make sense for its type).

### 2.3 Comments

As in §2.2: `(* … *)`, properly nested. An unclosed comment is an error.

### 2.4 Identifiers (§2.4)

* **Alphanumeric identifiers** are as in the Definition.
* **Symbolic identifiers** are omitted, except these from the initial basis:
  `+ - * / ^ :: = < > <= >= <> @ ~`. They can be referenced but never bound (§3).
  (`!` and `:=` belong to the omitted references.)
* **Type variables:** `'a` is kept. Equality type variables `''a` are omitted.
* **Long identifiers** `strid1.….stridn.id` are kept with alphanumeric components only. A
  qualified symbolic identifier such as `Int.+` is omitted, except `Real.==` and `Real.!=`,
  needed for real equality (§9.3).

## 3. Fixity (§2.6)

`infix`, `infixr`, `nonfix` and `op` are omitted. The infix status of identifiers is therefore
fixed. The table follows SML's conventional initial fixities (Appendix C and the SML Basis
Library); using this table does not imply support for that library:

| Precedence | Associativity | Identifiers |
|---|---|---|
| 7 | left | `*` `/` `div` `mod` |
| 6 | left | `+` `-` `^` |
| 5 | right | `::` `@` |
| 4 | left | `=` `<>` `<` `>` `<=` `>=` |
| 3 | left | `o` |
| 0 | left | `before` |

(`:=` at precedence 3 is omitted with references.)

**Restriction F1.** An identifier with infix status may not be bound by any binding: no value
binding, pattern variable, constructor, datatype or type constructor, or structure. Without `op`
most such bindings can't be written anyway.

**Restriction F2 (current implementation).** `open` applies only to structures the program
supplies, never to the checker-provided bootstrap library structures. The current MLton
bootstrap sees a wider host environment than the checker: opening one of those structures
can rebind operators or introduce members that the checker does not model. This restriction
keeps the two environments consistent while the custom Basis replaces the compatibility layer.
It is not a claim that the SubsetML Basis is a subset of the SML Basis Library.

Program structures cannot bind infix identifiers (F1). Qualified library access remains
available where a binding exists in the supplied environment. With F1 and F2, the operators
resolve to the fixed initial environment and retain their SML language behavior. Library
functions can have separately designed APIs; the parser's fixity table does not determine them.

## 4. Core grammar (§2.8, §2.9, Appendix B)

The tables list each phrase form and its status. A derived form (Appendix A) is kept exactly
when its equivalent form uses only kept features.

### 4.1 Expressions

| Form | Status |
|---|---|
| `scon`, `longvid`, `( exp )`, `let dec in exp1 ; … ; expn end` | kept |
| application `exp atexp`, infix `exp1 vid exp2` | kept |
| `exp : ty` | kept |
| `fn match`, `case exp of match` | kept |
| `if exp1 then exp2 else exp3` | kept, except that `exp3` may not itself be an `if` expression (rule C1) |
| `exp1 andalso exp2`, `exp1 orelse exp2` | kept |
| `()`, tuples `(e1, …, en)`, lists `[e1, …, en]`, sequences `(e1; …; en)` | kept |
| record `{ lab = exp, … }` | kept, under §6 |
| selector `# lab` | kept for alphanumeric labels, under §6; `#1`, `#2`, … omitted (R4) |
| `op longvid` | **omitted** |
| `raise exp`, `exp handle match` | **omitted** |
| `while exp do exp` | **omitted** |

### 4.2 Patterns

| Form | Status |
|---|---|
| `_`, special constants other than real (real is excluded by §2.9 anyway), `longvid` | kept |
| constructor application `longvid atpat`, infix `pat1 vid pat2` | kept |
| `pat : ty`, `()`, tuples, lists, `( pat )` | kept |
| record `{ lab = pat, … }` and the punning forms `{ lab, … }` / `{ lab : ty, … }` | kept, under §6 |
| wildcard row `{ …, ... }` | **omitted** |
| layered `vid <: ty> as pat` (and `{ lab as pat }`) | **omitted** |
| `op` in patterns | **omitted** |

### 4.3 Type expressions

| Form | Status |
|---|---|
| `tyvar`, `tyseq longtycon`, `ty1 * … * tyn`, `ty -> ty`, `( ty )` | kept |
| record type `{ lab : ty, … }` | kept only as the whole right-hand side of a `type` binding (§6) |

### 4.4 Declarations

| Form | Status |
|---|---|
| `val tyvarseq valbind`, including `rec` | kept |
| `fun tyvarseq fvalbind` (the derived function-value binding) | **omitted**: write `val rec f = fn match` |
| `type typbind` | kept |
| `datatype datbind` | kept |
| `open longstrid1 … longstridn` | kept for program-supplied structures (§7), subject to F2 |
| `dec1 ; dec2`, `dec1 dec2`, empty | kept |
| `datatype tycon = datatype longtycon` (replication) | **omitted** |
| `datatype … withtype …` | **omitted** |
| `abstype … with … end` | **omitted** |
| `exception exbind` | **omitted** |
| `local dec1 in dec2 end` | **omitted** |
| `infix`, `infixr`, `nonfix` | **omitted** |

**Restriction C1 (no `else if`).** The `else` branch of a conditional may not start with `if`.
Write the nested conditional in parentheses, `else (if … then … else …)`, which corresponds to
Workman's `else { if … }`, or use `case`. SML has no `if` without `else`, so that needs no rule.

All syntactic restrictions of §2.9 apply unchanged: no duplicate labels, no duplicate bindings in a
`valbind`/`typbind`/`datbind`, no repeated type variable in a `tyvarseq`, `rec` bodies must be
`fn match`, `true false nil :: ref` cannot be bound, `it` cannot be bound by a `datbind`, no real
constants in patterns, and no type variable scoped by two nested `val`s.

## 5. Static and dynamic semantics of the Core

These are unchanged (§4, §6), including the parts that are easy to get wrong:

* **Value restriction** (§4.7, §4.8): only non-expansive bindings are generalised.
* **Equality attribute** (§4.4, §4.6): `=` and `<>` have type `''a * ''a -> bool` internally.
  Equality type variables still arise during inference even though `''a` can't be written. `real`
  does not admit equality.
* **Overloading** (Appendix E): `abs ~ + - * div mod / < > <= >=` are overloaded over the
  classes of Appendix E restricted to SubsetML's types (`real`, `string`, `char`). Unresolved
  overloading defaults to `int` in SML, which SubsetML omits (§9.3), so an overloaded identifier
  whose type its context does not determine is rejected: `fn (x, y) => x + y` needs an annotation
  such as `(x : real, y)`.
* **Exceptions still exist dynamically.** The language can't declare, raise or handle them, but
  the Definition's dynamic semantics still produces packets: `Match` (failed `fn`/`case`), `Bind`
  (failed `val`). Current bootstrap host calls can also raise exceptions such as `Subscript`
  or `Io`; those are compatibility-layer behavior, not the custom library's failure API.
  Because nothing can handle an exception packet, it always reaches
  the top level, where §8 applies: execution of that program phrase fails and the basis is not
  extended.
* **Match warnings** (§4.11): non-exhaustive and redundant matches are warnings, not errors, as in
  the Definition.

## 6. Records

SML records are structural. Workman's are nominal. SubsetML keeps SML's structural meaning but
restricts records so that every record type has a name and no two names share a shape, which
makes the structural and nominal readings agree.

* **R1.** A record type expression `{ lab1 : ty1, …, labn : tyn }` (n ≥ 1) may occur only as the
  whole right-hand side of a `type` binding, e.g. `type point = { x : real, y : real }` or
  `type 'a cell = { value : 'a, label : string }`. These are *record type declarations*.
* **R2.** No two record type declarations in a program may have the same set of labels.
* **R3.** Every record expression and record pattern must have exactly the label set of a record
  type declaration in scope. The elaborated type is still the structural record type of the
  Definition; R3 is a check, not a reinterpretation.
* **R4.** Numeric labels and the empty record are not written in record syntax. Tuples and `()`
  are written with tuple syntax. Tuple selectors `#1`, `#2`, … are omitted: take tuples apart
  with patterns such as `(_, x)`. (Workman has no tuple projection, and the tuple's width, which
  a translation would need, is only known from its type.)
* **R5.** `# lab` keeps the Definition's meaning (the derived form
  `fn {lab = var, ...} => var`): the program context must determine the record type uniquely
  (§4.11). The `...` wildcard itself can't be written (§4.2).

## 7. Modules (§3, §5, §7)

Only top-level structures are kept, the counterpart of a Workman file.

```
topdec ::= strdec
strdec ::= dec
         | structure strid = struct dec end ⟨and strid = struct dec end …⟩
         | strdec1 ⟨;⟩ strdec2
         | (empty)
```

| Form | Status |
|---|---|
| `structure strid = struct dec end` at top level | kept |
| structure declarations inside `struct … end` (nesting) | **omitted** |
| any other `strexp` (`longstrid`, `let … in strexp end`, ascription) | **omitted** |
| `local` at structure level | **omitted** |
| `signature`, `sig … end`, `:`/`:>` ascription, `where type`, sharing, `include`, `eqtype` | **omitted** |
| `functor` declarations and applications | **omitted** |

**Restriction M1.** A source file contains at most one structure (a single `strbind`), alongside
any other top-level declarations. Each file corresponds to one Workman module: the structure
`FooBar` lives in `foo_bar.sml`, which becomes `foo_bar.wm`, and the file's other top-level
declarations join that module.

Long identifiers may still have several qualifiers when the supplied library environment
contains nested structures. `OS.Process.exit` is an example in the current bootstrap layer.

## 8. Programs (§8)

```
program ::= topdec ; ⟨program⟩
          | exp ; ⟨program⟩        (derived form: val it = exp)
```

Execution follows §8 exactly. A phrase that fails to elaborate has no effect. A phrase whose
evaluation yields a packet leaves the basis unchanged, but side effects that happened before the
packet was raised (such as output) remain. For source *files*, the Definition leaves the treatment of errors to the
implementation, and SubsetML aborts the file at its first failing phrase. The final `;` before the
end of a file may be omitted.

## 9. Initial language environment

### 9.1 Definition basis (Appendices C, D)

| Component | Status |
|---|---|
| types `unit bool real string char list` | kept |
| type `int` | **omitted** for now (§9.3) |
| types `word`, `ref`, `exn` | **omitted** |
| `true false nil ::` | kept |
| `=` | kept |
| `ref`, `:=` | **omitted** |
| `Match`, `Bind` as identifiers | **omitted** (still raised dynamically, §5) |
| overloaded identifiers (Appendix E) | kept, resolving to `real`, `string` or `char` (`div` and `mod` omitted) |

### 9.2 Bootstrap namespace restriction

The current checker uses a bootstrap library environment described by `src/basis.sml`.
Its compatibility interfaces and their replacement are documented separately in the
[SubsetML Basis](basis.md#current-implementation-and-migration).

**Restriction B1 (current bootstrap).** The checker currently prohibits binding omitted SML
constructors as value variables: `ref`, `Match`, `Bind`, `Chr`, `Div`, `Domain`, `Empty`,
`Fail`, `Option`, `Overflow`, `Size`, `Span`, `Subscript`, `Io`. These constructors remain visible
in the MLton host environment, where a same-spelled pattern would have a different meaning.
Rebinding them as datatype constructors is allowed. This is a bootstrap compatibility guard;
this restriction can be revisited when the checker and host use the same supplied environment.

### 9.3 Numbers: `real` only, for now

**Decision (2026-10-02):** SubsetML omits `int`. Its only numeric type is `real`, which is
exactly Workman's `Number` (64-bit IEEE, `../wm-mini/markdown/core-design.md`, "Numbers"), so
`real` and `Number` translate one for one. `int` is expected to return later, to SubsetML and to
Workman together.

Because SubsetML stays strict SML, this also means:

* **No integer constants.** `42` has type `int` in SML, so numbers are written as real constants:
  `42.0` (Workman `42`).
* **Overloading must resolve to `real`** (or `string`/`char` for comparisons). SML would default
  an unresolved `+` to `int`, so SubsetML rejects it instead (§5).
* **No `=` on numbers.** `real` does not admit equality in SML: compare with `Real.== (x, y)`
  (Workman `==`), and numbers cannot appear in patterns. A datatype holding a `real` does not
  admit equality.
* **The integer-only `div` and `mod` bindings are omitted.** Numeric library operations and
  sizes/indices use the currently supported number type. Library numeric APIs and bootstrap
  adapters are documented in the separate [Basis document](basis.md).

The checker enforces this restriction and the implementation uses `real` throughout.

## 10. Implementation-defined choices

| Point | SubsetML choice |
|---|---|
| Errors while including a file (§8) | abort that file at the first failing phrase |
| Context resolving overloading (Appendix E) | the smallest enclosing `val` declaration. Appendix E allows a smaller context than the structure-level declaration. |
| Context resolving `# lab` (§4.11) | the same as overloading |
| Character set | 8-bit, ASCII-compatible |

## 11. Open questions

* Whether to add the `word` type.
* Structure aliases `structure A = B`.
* Numeric overloading (Appendix E): with `real` as the only number type it always resolves to
  `real` (§9.3). Whether to keep it once `int` returns is open.
* Whether to require exhaustive matches, which would remove `Match` at runtime for native code.
  That is an extra restriction, so the Definition allows it.
