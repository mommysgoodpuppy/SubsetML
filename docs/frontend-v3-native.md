# Frontend-v3 native portability decisions

Status: the portable lexer translates and passes a disposable MLton smoke build.
Entry-driven native builds and full WM/native parity checks remain pending.
This document records decisions separately from implementation status and open questions.

## Target and references

The proposed first milestone is frontend-v3's lexer running through Workman → SubsetML →
MLton, with matching tokens, trivia, spans, marks and delimiter mates. Structural parsing
is still pending in frontend-v3. Its explorer and Deno debug driver are separate consumers,
not prerequisites for the first native lexer.

- [Frontend-v3 contract and conventions](../../wm-mini/tooling/frontend-v3/README.md)
- [Lexer entry](../../wm-mini/tooling/frontend-v3/src/lexer/lexer.wm)
- [Lexer regression tests](../../wm-mini/tests/frontend_v3_lexer_test.ts)
- [Current translation](translation.md)
- [Source module loading](module-loading-plan.md)
- [SubsetML Basis](basis.md) and [text design](text-design.md)

Portable library algorithms belong in source where practical. Translating a Workman feature
does not automatically require adding that feature to the SubsetML language: lowering may
produce ordinary SubsetML instead. The target must preserve evaluation order and observable
behavior except for explicitly agreed differences recorded below.

## D1: Panic exits the process

Decision: for this portability target, lower a call to Workman's built-in `Panic(message)`
to `SubsetProcess.panic message`.

```sml
SubsetProcess.panic message
```

`SubsetProcess.panic` has type `string -> 'a`; the lowering fits any result position, evaluates
its argument once and retains its string constraint. The source Basis implementation attempts
to write the message followed by a newline to stderr, then exits unsuccessfully even if
validation or writing fails. It uses existing text extraction, stderr and exit operations;
there is no new host requirement. Supply its existing process/I/O dependencies in native builds.

This supersedes the initial exit-only decision that discarded the message. The message is a
SubsetML byte string; no implicit Unicode conversion is introduced.

Frontend-v3 uses `Panic("unreachable")` to assert invariants in otherwise covered branches.
The lowering stops execution if such an assertion is violated. It does not require the
translator to prove the branch unreachable, erase it, or add an unreachable expression to
the SubsetML language. It preserves the supplied diagnostic message when stderr writing succeeds, but does not
reproduce Workman's diagnostic formatting or any ability for a surrounding host to catch the
failure: process termination is the agreed target behavior.

Recognize the resolved built-in, rather than rewriting an unrelated binding merely named
`Panic`. First-class uses of the built-in need a separate translation rule if encountered.

Implementation status: source Basis panic and resolved built-in lowering are implemented.
Reverse translation selects its canonical provider with `--panic-runtime FILE.wm`; generated
private dependencies and SML metadata are added only for actual built-in uses. First-class
uses, local shadowing, the runtime type contract and dependency cycles have focused coverage.

## Text: portable implementation direction

Discussion outcome: UTF-16 text is primarily portable implementation work, rather than a
reason to enlarge the host kernel. Preserve frontend-v3's text contract rather than silently
changing its offsets to byte offsets.

Frontend-v3 counts UTF-16 code units and explicitly diagnoses lone surrogates in literals.
Its [character access](../../wm-mini/tooling/frontend-v3/src/lexer/character.wm) and
[reader](../../wm-mini/tooling/frontend-v3/src/lexer/reader.wm) now use numeric UTF-16 source units.
A portable representation must retain arbitrary code units, support indexed access and
slicing, and preserve source spelling. The existing strict Unicode codecs reject malformed
surrogates; they are not an interchangeable representation for damaged editor buffers.

The initial Basis representation is now implemented as `SubsetUtf16Source`: a balanced raw-unit
index with shared slice views, checked construction, Option lookahead and strict UTF conversions.
It uses only existing primitives. Frontend-v3 reader integration and source-view trivia are implemented; native build
generation remains pending; this is not yet a native lexer. Do not add host requirements for
algorithms expressible in SubsetML within reason.

## D2: Lower numeric and pinned-value patterns to conditional checks

Frontend-v3 contains numeric patterns and pinned-value patterns, such as
`Char.classLetter`, that cannot be represented directly as SubsetML patterns. Decision:
lower these into ordinary patterns plus conditional checks, preserving:

- One evaluation of the match subject.
- Source branch order and fallthrough when a check fails.
- Binding scope, constructor identity and hygienic generated names.
- The source equality operation; numeric checks use real comparison, not SML equality.

This decision does not add numeric patterns, pinned patterns or guards to SubsetML's
authored syntax. A Workman translation representation may need to retain these constructs
until checking and lowering can resolve their meanings. The reverse parser retains pins in an internal translation-only pattern node, then shared
binding resolution and ordered checks remove it before target checking. Numeric literals
become real comparisons without extending authored SubsetML pattern syntax.

When a nested pattern's conditional check fails, continue to the next source branch rather
than reporting a match failure. Generated conditionals must use nested expressions in each
language's supported syntax; neither SubsetML nor Workman supports an `else if` form.

For example, the SubsetML output for two numeric alternatives has this shape:

```sml
if Real.== (code, 97.0) then handleA ()
else (if Real.== (code, 98.0) then handleB ()
      else handleOther ())
```

The corresponding Workman nesting uses `else { if (...) { ... } else { ... } }`.
Portable Workman sources do not need to rewrite these patterns manually.

Implementation status: numeric and pinned match lowering is implemented. Focused native tests
cover nested fallthrough, subject evaluation once, outer-value capture despite shadowing, real/
string/variant comparisons, and ordinary non-exhaustive Match failure. Numeric/pinned let
binding patterns remain outside the reverse profile; unsupported comparisons are rejected.

## D3: Record updates name their nominal record type

Decision: frontend-v3 record updates must use explicitly named record literals:

```wm
Point { ..point, x = 10 }
Token.Token { ..tok, mateIdx = Token.Mate(openIndex) }
```

Reject spread inside anonymous `.{ ... }` literals during translation, with a diagnostic
requesting the named form. This restriction applies to updates; it does not prohibit anonymous
record literals without spread.

Resolve the named record through the module/type environment and look up its declared field
list. Reconstruct the complete record in SubsetML, with temporary bindings preserving once-only
evaluation and source order for spreads and explicit fields. Preserve source override precedence.
The target checker must still verify that spread operands have the expected type and replacement
fields have the required types. Unknown record names and fields are errors, not inferred guesses.

The explicit name supplies the layout needed for lowering, so record reconstruction does not
require implementing general inference in the translator. Imported and generic record declarations
still require name resolution and type-parameter handling.

Implementation status: frontend-v3's seven updates use named literals. Reverse translation now
collects record declaration layouts across supplied files, reconstructs named literals and updates,
and rejects anonymous spread. It supports generic layouts instantiated at concrete types, checks
overridden entries too, and preserves source evaluation/override order using a polymorphic helper.
Imported types get a private local alias to satisfy SubsetML's existing record-scope rule.
The initial layout collector accepts top-level record declarations; nested declarations are
diagnosed rather than guessing their scope. Header namespace imports now resolve through canonical file identities, with aliases rewritten
before record-layout collection. Colliding basenames receive distinct backend names and imported
modules retain their original declarations. Named, open-only and later imports remain outside the initial profile; generated header opens
after namespace imports are retained for compiler round trips. Field-type witnesses preserve
private dependency scope during imported record reconstruction.
This remains the explicit source-list workflow; graph-driven translation is separate work.

The frontend-v3 fallback audit found no new recovery policy or ignored failure: these edits only
name the existing record types. No wildcard branch, invariant panic or reader behavior changed.
The lexer regression test passes after migration.

## D4: Preserve portable carrier let-polymorphism

Decision: preserve non-expansive pure record literals, and use eta expansion for eligible
function-record copies and field aliases. Keep ordinary partial applications restricted. Do not
change WM's generalization rules or add higher-rank record fields.

The [Result carrier investigation](carrier-portability.md) verifies the rank-1 pattern with
WM, MLton and SubsetML. The [detailed lowering design](carrier-lowering.md) specifies purity,
argument shape, shared type constraints, ordered effects and keyword-safe spelling.

Implementation status: eligible pure named literals now retain non-expansiveness, including
polymorphic `Box { value = [] }` and Result-style carriers with independent parameter roles.
Imported layouts receive private aliases. WM names such as `fn` receive consistent, hygienic
SML spellings. Uppercase generic parameters in aliases and datatypes are resolved as parameters.

Eligible module-level function-record copies and field aliases are now implemented. Copy
wrappers preserve the checked construction's inferred layout arguments, including relationships
shared between fields, using a whole-record annotation. Function aliases are probed in their
static environment and wrapped only when the selected value is a function. Declared field names
and arities alone are insufficient for copies. Correlated literal layouts still use the checked helper fallback;
concrete instantiations work, but some pure source bindings still lose generalization there.
Arbitrary polymorphic non-function copies remain a discussion boundary.

## Backend naming checkpoint

The shared `BackendNames` pass now runs before reverse-translation checking. It resolves
lexical value/type bindings and imported exports, maps record labels consistently, retains
constructor status and records source/backend spellings for diagnostics. Reserved constructor
names such as `Span` are handled by the same policy as unsafe SML keyword bindings, rather
than by a record-specific workaround. Duplicate source bindings remain rejected.

Positional record constructor functions now preserve declaration field order, generic types
and first-class references. Frontend source/mark/character modules translate after these
changes. Numeric/pinned match patterns now lower successfully; the isolated full lexer probe
passes this step and built-in Panic with an explicitly selected native runtime. The full
build workflow and complete parity checks are still pending; the selector defect below is fixed. The probe uses the existing SML checker text adapter rather
than attempting to translate the JS host adapter.

## Remaining topics

- Header namespace aliases and canonical identity are implemented for reverse source-list
  translation, including private checking environments and generated SML comment metadata.
  Entry-driven discovery is now implemented for the same header namespace profile.
  Generated MLton scopes are now implemented for the resolved entry graph.
  Named/open-only/later imports remain outside the initial profile. Explicit native adapter
  selection is now implemented, as described below.
- Generic type parameters: extend constraint-preserving literal lowering beyond the initial
  independent-parameter shapes.
- Debug templates, printing and `Result.debug`: choose their portable treatment and distinguish
  debug-only consumers from lexer behavior.
- Native/Workman comparison harness: exercise ordinary text, Unicode and damaged input;
  compare the lexer document rather than only successful compilation.

These are discussion topics, not additional settled decisions or implemented features.

## Resolved conformance defect: selector dependencies and declaration closure

The lexer source-list probe passes source, mark, character, token, reader, read, string and
trivia modules, then fails in pair's branch-local `token.span.endPos.index`. The receiver's
complete type is already present in `tokens : Token.Token list`; this is not missing WM
record disambiguation information or a missing Basis function.

Plain constrained SML reproduces the discrepancy (MLton compiles it; SubsetML rejects
`#endPos`):

```sml
structure Probe = struct
  type position = { index : real }
  type span = { endPos : position }
  type row = { span : span }
  val read = fn (rows : row list) => case rows of
      row :: _ => let val endIndex = #index (#endPos (#span row)) in endIndex end
    | [] => 0.0
end
```

The Definition audit shows that this is a general selector/closure conformance defect,
not a case-specific frontend exception. Appendix A defines `case e of match` as
`(fn match)(e)` and `#lab` as a function with a flexible record pattern. Section 4.10's
application/match rules share their types; section 4.8 closes a value binding only over type
variables absent from its context; section 4.11 requires the program context to determine
the flexible record's full label set. These are declarative rules, not a mandated procedural
inference order. SubsetML spec R5 explicitly retains the Definition's selector semantics.

The current checker rejects both the case and its derived function application, and also
rejects a whole-function type constraint that MLton accepts. Therefore the earlier proposal
to seed only case rules with the subject type is insufficient. The narrow underlying problem
is that pending selector constraints carry record and field types separately, while ordinary
unification lowers levels only through actual type structure. A receiver tied to the outer
context can have a still-local field variable; a nested selector then falsely appears
independent of that context and is rejected at an inner declaration's closure.

An isolated temporary compiler experiment propagated receiver scope levels into field types
for pending selections, iterating along selector chains before closure. It agreed with MLton
on all six focused probes:

| Probe | Before correction | Corrected checker / MLton |
|---|---|---|
| Typed subject, nested projection in case-local declaration | rejects | accepts |
| Equivalent `(fn match)(subject)` | rejects | accepts |
| Whole-function input type constraint | rejects | accepts |
| Truly unresolved separate helper | rejects | rejects |
| Captured field used as both real and string | rejects | rejects |
| Independent polymorphic local function beside the selectors | rejects | accepts |

The general correction is now implemented in `Elab.settleSelections`. For an unknown
receiver, lower the field type's free-variable levels to the receiver's level, and repeat
until selector resolution and scope propagation reach a fixed point. This preserves the
context dependency represented by the pending row constraint before checking declaration
closure or generalizing local bindings. Truly unresolved rows still fail at their enclosing
declaration boundary. No case-specific inference rule or frontend annotation was added.

`tests/selector-scope.sh` compares nine valid/invalid constrained SML probes with MLton,
executes accepted programs, and checks accepted compiler round trips. It covers equivalent
case/application forms, whole-function constraints, captured aliases, independent local
polymorphism, unresolved rows, captured-field monomorphism and invalid field selections.
The constrained compiler selfcheck, compiler bootstrap and existing 100 checker cases pass.

Reference implementation inspection supports this treatment: MLWorks recursively propagates
levels through flexible/ordinary record types and their fields in
`/home/ellie/git/mlworks/src/typechecker/_unify.sml:330`; MLton stores scope times on flexible
record types and uses them during unification/generalization in
`/home/ellie/git/mlton/mlton/elaborate/type-env.fun:48`. These are implementation references;
the Definition's context/closure rules remain the authority. MLWorks was inspected as source,
not executed as a reference compiler.

The full portable lexer now translates, builds with MLton using the existing native adapters,
and passes a smoke document containing template interpolation and a damaged block comment.
This is a manually assembled, disposable build probe, not the planned entry-driven build or
complete WM/native parity suite. Full flexible-row unification remains a possible later design;
this fix needs no new Basis API or record-name guessing.

Definition source references: Appendix A `app1.tex:122–128`; closure `statcor.tex:456–489`;
application `statcor.tex:690–695`; matches `statcor.tex:738–760`; flexible record restriction
`statcor.tex:1360–1371`. Sources are in the sibling wm-mini research checkout.

Built-in WM list calls in pair/string/trivia now use the already available portable
`SubsetList` operations explicitly. No Basis API expansion was needed.

## Entry discovery checkpoint

`sml-entry OUTDIR [--panic-runtime R.wm] ENTRY.wm` discovers and translates the canonical
reachable graph through the existing source-list lowering/checking pipeline. The frontend
lexer is now translated from its entry and runtime roots alone in the staged native probe.
`tests/wm-entry.sh` executes a diamond graph to verify once-only initialization and import
order, and checks symlink identity, distinct same-basename modules, private scope, missing
files, cycles and unsupported import diagnostics. The panic lowering regression now exercises
runtime closure discovery as well. `sml-entry` now emits `project.mlb` with private per-module
bases and entry-only exports. The diamond executes once in source order through that generated
build; native tests reject injected sibling references and leaked dependency structures. A
WM-authored lexer smoke entry also builds/runs through the generated MLB after substituting
the existing native SML host adapters in the staging tree. Explicit adapter selection now
removes that substitution step, as described below. Reusable native driver tooling and
complete token/trivia/mark/mate parity remain unfinished.


## Native adapter selection checkpoint

`sml-entry` now accepts repeatable `--native-adapter CHECKER.wm NATIVE.sml STRUCTURE`
options. The canonical checker identity selects the replacement; the generated MLB supplies
private source import aliases and exports the native structure under the graph's allocated
name. Generated checker files remain intact. The full WM-authored lexer smoke entry builds
and runs through this mechanism with the existing native host/text adapters; no output-file
substitution is needed. `tests/native-adapters.sh` verifies duplicate-basename separation,
symlink selection, dependency type identity, once-only initialization, hidden native exports,
and invalid selections with no partial output. Native lexer staging/driver tooling and complete
WM/native document parity are still pending. See `translation.md` for the CLI contract.


## Reusable native lexer baseline

The frontend now has a WM-authored native file driver and portable complete-document encoder.
The wm-mini build script stages source-generated Basis checker WM, selects native adapters by
canonical identity and compiles the generated MLB. The parity script compares full documents
for 126 raw UTF-16 buffers and 121 strict UTF-8 inputs with WM results and an independent JS
normalization. Encoding failure checks cover overlong UTF-8, encoded surrogates, truncated
sequences and odd raw-unit byte lengths. BOMs remain ordinary source units.

The hyphenated driver filename exposed unsafe module hints. `BackendNames.moduleHint` now
provides separator normalization and safe empty/digit-leading prefixes; the canonical planner
still allocates distinct names for collisions. Focused native entry/name/adapter regressions,
constrained selfcheck, regeneration and bootstrap pass. No Basis API change was needed.
Parser design remains the next frontend phase; this checkpoint proves the lexer baseline.


## Embedded declaration removal

Decision: drop embedded SML declarations from WM translation. The line-start `val`/`datatype`/
`open` scanner is removed, so keyword record labels are ordinary WM tokens. Header open imports
use internal resolved nodes instead of SML text. Source SML checker semantics are unchanged;
unsupported forward declaration forms fail explicitly before any generated output, including
inside nested functions. Expression compatibility forms remain independent of this removal.
The compiler's own generated WM has no embedded declarations; bootstrap remains supported.

The surface AST now gets past `Delimited.open` and reaches intentional subset rule R2:
`TypeArguments<T>` and `TypeParameters` both have the record label set `{angles}`. This is
recorded for discussion, not resolved by renaming source fields or relaxing the checker.


## Distinct nominal record shapes

Decision: retain R2 and use a temporary frontend coding convention requiring distinct complete
field-label sets for distinct nominal records. Shared individual labels remain allowed. Use
meaningful distinguishing labels rather than adding dummy fields or changing the lowerer;
reconsider automation with a future compiler-informed WM-to-SubsetML lowerer.

The surface AST now uses `argumentAngles`/`parameterAngles` and `blockPhrase`/`topPhrase`
for the two colliding pairs. The full AST translates through the canonical entry graph and
passes MLton type checking; its WM compilation also passes. Nominal identities are retained,
and no checker/lowering/Basis changes were needed.
