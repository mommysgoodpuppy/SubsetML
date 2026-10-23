# Result carrier portability investigation

Status: the core carrier/error-procedure pattern was checked and executed with Workman and
MLton. The investigation itself does not change Workman's rules. The subsequent
[lowering design and implementation](carrier-lowering.md) preserves eligible pure named literals
and fixes keyword spelling; eligible module-level function copies and aliases are now lowered too.

Run the reproducible probes from the repository root:

```sh
python3 tests/carrier-portability/run.py
```

The probes require MLton, `wm`, Deno and the sibling wm-mini checkout. They check reference WM
source against WM's real checker, compile explicit SML encodings with MLton, check those SML
encodings with SubsetML, and compare runtime output for the four accepted executable cases.
The SML encodings are hand-written candidate translations, not output from the current WM
translator. They deliberately map WM's `fn` label to the legal SML label `fn_`.

## Main finding

The Result carrier does not require higher-rank polymorphism or polymorphic record fields.
Its fields each have one instantiated function type. A pure let-bound record of those functions
is generalized as a whole, and each occurrence of the carrier instantiates that scheme afresh.
This is ordinary rank-1 let-polymorphism, supported by MLton and SubsetML.

The SML probe models all seven fields of WM's current
[Carrier declaration](../../wm-mini/std/monad.wm), the pure
[Result carrier](../../wm-mini/std/result.wm), and their data-first combinators and curried
`via`/`viaError` adapters. It tests:

- One shared carrier used with unrelated success and error types.
- Independent instantiations of `map` and `map2` fields.
- Error injection from stage-specific failures into an application error datatype.
- Flat procedures with different intermediate payload types.
- Failure propagation without running a later transformation; the probe detects unexpected
  output if the skipped stage runs.

The existing direct `SubsetResult.via` and `viaError` API remains portable too. A carrier record
provides another level of indirection, rather than changing the polymorphism required by a
single procedure stage.

## Typing and execution results

| Probe | WM | MLton / SubsetML | Meaning |
|---|---|---|---|
| `shared` | accepts; runs | accepts; runs | Pure shared function-record carrier instantiates independently. |
| `procedure` | accepts; runs | accepts; runs | Heterogeneous stages, error injection and failure skipping work. |
| `partial` | rejects | rejects | A saved ordinary partial application is monomorphic in both languages. |
| `eta` | accepts; runs | accepts; runs | Wrapping that partial application in a function restores let-polymorphism. |
| `parameter` | rejects | rejects | Passing a carrier as a parameter does not give its fields rank-2 polymorphism. |
| `copy` | accepts | rejects | Pure WM spread generalizes; reconstructed SML field projections are expansive. |
| `projection` | accepts | rejects | WM can generalize a dotted function-field alias; SML's selector application is expansive. |
| `copy_eta` | accepts; runs | accepts; runs | Eta-expanded function fields repair the tested SML carrier copy. |

The negative probes use incompatible real/string payloads rather than relying on the printed
names of inference variables. The accepted probes also exercise independent string/bool error
types, so success is not explained by accidentally fixing the carrier to one error type.

### Partial application is already restricted in WM

```wm
let viaResult = Monad.via Result.carrier;
```

This binding does not promise a universally reusable adapter. Its types are fixed by its uses.
Reusing it across unrelated payload/error types fails in WM and MLton. A portable reusable
adapter is instead a function:

```sml
val viaResult = fn f => fn result => via carrier f result
```

Naming a concrete stage through partial application is still useful: the procedure probe does
exactly that. Each stage has one input/output/error signature.

### Carrier parameters are monomorphic within an invocation

A parameter such as `domain` has one record type throughout the function body. Its adapter field
cannot be used first at real payloads and then at unrelated string payloads in that invocation.
Neither WM nor SML promises otherwise. This is different from separate occurrences of the
let-bound global carrier, whose scheme is instantiated independently.

### Copying function records has a portable encoding

SML's `#fn_ carrier` is an application of a selector function. Putting that expression directly
into a new record makes the record expansive. For the tested carrier, fields can instead be
wrapped as functions:

```sml
val copied = {
  fn_ = fn f => fn result => (#fn_ carrier) f result,
  fnError = fn inject => fn f => fn r => (#fnError carrier) inject f r,
  succeed = fn x => (#succeed carrier) x,
  map = fn pair => (#map carrier) pair,
  map2 = fn triple => (#map2 carrier) triple,
  andThen = fn pair => (#andThen carrier) pair,
  mapErr = fn pair => (#mapErr carrier) pair
}
```

The executable reconstruction is in [copy_eta.sml](../tests/carrier-portability/copy_eta.sml).
Its fields are syntactic function
values, so the whole record is generalized. It preserves the tested immutable carrier's behavior.
It is not a general translation rule for arbitrary spreads. The implemented rule handles eligible
plain function-record copies, with an inferred whole-record annotation retaining shared types.
More complex updates retain ordered lowering to preserve effects and discarded-entry constraints.
Function wrapping also does not solve polymorphic copied fields that are not functions.

## SML keyword gap: now fixed

WM's `fn` is both a function binding name and a carrier field label. SML reserves that word.
The initial translator emitted that label unchanged, causing MLton syntax errors independently
of generic carriers or the value restriction. The translator now applies a collision-safe naming
prefix consistently across declarations, labels and uses in the supplied source batch. The probe
checks that a translated monomorphic `fn` record passes MLton syntax/type checking.
The manual `fn_` spelling remains in the comparative SML encodings to isolate typing behavior.
See [the naming policy](carrier-lowering.md#sml-keyword-spelling-implemented) for details.

## Implications and limits

The findings favour preserving the existing pure-carrier pattern rather than restricting all
WM record construction to accommodate helper-based lowering. A pure record literal of named
functions has an ordinary non-expansive SML representation. The first helper-call lowering
lost that property; the eligible literal fast path now preserves it without imposing a source restriction.

Pure spreads and dotted field aliases are genuine source/target differences. Restricting only
spreads would not address field aliases. Conversely, function-record reconstruction offers a
possible target solution without changing WM's generalization rules.

This is a focused Result investigation, not a repository-wide breakage audit. It does not prove
that every generic WM program is portable, implement namespace-to-carrier coercion, or cover
lifted operator/tuple syntax. Task's carrier uses the same rank-1 type pattern, but its actual
asynchronous execution and JS host boundary were not ported or tested under MLton here.

No WM generalization rule or frontend-v3 implementation was changed by this investigation.
