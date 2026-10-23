# Preserving portable carrier values during WM → SubsetML translation

Status: pure named literals, keyword mapping, and eligible module-level function-record copies
and function-field aliases are implemented. The reference semantics and executable
manual encodings are recorded in [the carrier investigation](carrier-portability.md).

## Contract

Preserve ordinary rank-1 let-polymorphism when the source binding permits it. Do not add
higher-rank fields, change WM's value restriction, specialize reusable carriers, or silently
remove constraints to make generated SML type-check. Each use of a let-bound carrier can
instantiate its scheme independently; a carrier passed as a function parameter still has one
instantiation within that invocation.

Source evaluation order, override precedence and once-only evaluation remain part of the
contract. Wrapping a function must not defer an effectful computation that originally happened
while constructing the record. Generic types and keyword spellings must agree across modules.

## Pure named literals: implemented first slice

The ordered helper used for record updates is an application, hence expansive in SML. A plain
record of values is non-expansive. Preserve the latter form for eligible literals:

```wm
record Box<T> = { value: T };
let empty = Box { value = [] };
let numbers: Box<List<Number>> = empty;
let texts: Box<List<String>> = empty;
```

This now becomes a direct record value and both uses compile with MLton. Imported layouts
receive a private local type alias before value declarations, making their labels visible under
SubsetML's record-scope rule. The alias adds no runtime evaluation or new type identity.

The initial eligibility check is deliberately conservative:

- There is no spread, and every field expression is syntactically pure: a constant, identifier,
  lambda, or recursively pure record, tuple, list or type annotation. Calls and computed field
  selections use the existing helper path. Constructor calls are not classified specially yet.
- Each declared generic parameter occurs exactly once across the entire layout.
- A generic field is either one parameter or a function from one parameter (or a tuple of
  parameters) to one result parameter. Fields without generic parameters are also supported.

These rules cover the independent parameter roles of the current WM Carrier declaration.
They are a translation fast path, not new restrictions on WM or SubsetML source syntax.

Fixed field types retain explicit annotations. Generic function fields receive a single lambda
wrapper enforcing their declared outer argument shape. A two-argument WM field receives one
SML tuple argument, rather than accidentally inferring a unary field. The result parameter
remains inferred, including any constraints introduced by the actual function implementation.
Further curried arrows come from that implementation; only one outer wrapper is necessary
to make the field a value.

For example, after keyword mapping:

```sml
val carrier = {
  subsetmlKeyword_fn = fn argument => resultFn argument,
  map = fn (wrapped, transform) => resultMap (wrapped, transform)
}
```

Wrapping a pure identifier or lambda does not move construction effects. The wrappers have
fresh local argument names. Literal fields retain authored order; missing, unknown and duplicate
fields still produce errors before any output is written.

A correlated layout such as `Identity<T> = { run: T -> T }` is outside this first fast path.
Dropping its annotation would permit `run` to have different input and output types. It therefore
keeps the checked helper lowering. Concrete instantiations work; generalizing such literals
needs a subsequent phase that preserves the inferred type relationships.

## Ordered construction and updates: existing fallback

Keep the polymorphic layout helper for expansive literals and updates. Its argument tuple
evaluates source entries once, in authored order, including fields subsequently overwritten.
Spread operands and replacement fields remain checked against the same instantiated layout.
Later entries override earlier ones. An effectful literal or update does not become a generalized
value merely because some of its fields are functions.

The fallback still has the known limitation that a pure spread, or an otherwise unsupported
pure literal shape, may lose source generalization. This implementation does not claim that
every WM record is portable yet.

## Function-record copies: implemented typed phase

For an eligible pure function-record copy, reconstruct every final field as a function:

```sml
val copied = {
  fn_ = fn argument => (#fn_ base) argument,
  map = fn pair => (#map base) pair
}
```

The investigation confirms this encoding for Result's carrier. Automatic lowering must also
preserve the receiver's *instantiated type scheme*, not only its declared field names or arities.
For example, a scheme may tie the input types of two fields together. Selecting `base` separately
inside two wrappers instantiates a generalized `base` twice and could accidentally untie them.
The source spread instantiates its operand once. An explicit annotation can introduce such
relationships even when the layout declaration has independent parameters.

The translator now checks the original ordered helper construction in the declaration's current
static environment. It separately instantiates the named layout and unifies it with that checked
result. This recovers concrete arguments and correlations introduced by the receiver or any
replacement fields. It then eta-expands the final fields and annotates the entire record with
those exact inferred layout arguments. Repeated inferred variables use the same fresh SML
variable name; concrete arguments remain concrete.

For a coupled layout, the output therefore has a constraint such as:

```sml
val copied = {
  left = fn argument => (#left base) argument,
  right = fn argument => (#right base) argument
} : 'subsetmlCopyVariable Coupled.coupled
```

Each receiver occurrence still instantiates independently, but the whole-record annotation ties
those instantiations to the one layout instantiation inferred for the source construction. No
second inference engine or relaxed target value restriction is needed. The probe state is
discarded after generating the annotation; normal elaboration checks the emitted value, and
strict elaboration validates the complete rewritten module.

Eligibility in this first typed pass is limited to unannotated, non-recursive module-level
variable bindings, and the literal must be a plain `{ ..base }` copy. Every declared field must
be a function and the receiver must directly name an immutable value. Replacements and multiple
spreads keep ordered lowering: even a discarded pure field can constrain a captured monomorphic
variable. Checking that field in a discarded probe would not retain its constraint in the emitted
AST. A future rule for pure updates must retain those constraints explicitly. Expansive receivers
also keep ordered lowering.

Type arguments can contain functions, tuples, unit, ordinary nominal datatypes and closed
inference variables. Nominal names are recovered from the visible static environment, including
imported datatypes; shadowed bindings are skipped. Only identity aliases qualify as names for
nominal constructors. Equality-variable kinds are retained. Inference variables captured from
an outer monomorphic environment, rigid variables, unresolved overloads and structural record
type arguments without a portable spelling retain the checked helper fallback. Nested copies
and bindings with pattern annotations also retain that fallback for now.

The parser carries an internal copy plan containing the ordered construction, pure final fields
and named layout. This adds no surface SubsetML syntax. Any plan not consumed by typed lowering
checks and prints through its original helper construction, so unsupported contexts retain the
existing conservative behavior.

Arbitrary polymorphic non-function fields do not have a general eta-expansion repair; leave
them unsupported pending discussion.

## Function-field aliases: implemented first scope

WM can generalize a pure dotted field alias. SML's `#field receiver` is an application and is
expansive. The declaration pass probes a direct selection on a named receiver in its actual
static environment and settles pending selections. If the selected type is a function, emit
`fn argument => (#field receiver) argument`. One argument is sufficient: a tuple domain is
inferred as a tuple, and further curried arrows remain in the result type.

The receiver occurs once in this wrapper. Unlike a multi-field copy, there is no second
instantiation that could sever correlations within the selected function type. Normal
elaboration also retains captured monomorphic variables, so aliasing a function obtained by
partial application does not make it universally reusable.

The first scope is unannotated, non-recursive module-level variable bindings whose entire
right side is a direct field selection on an identifier. Computed receivers, chained selections,
nested declarations, destructuring and non-function aliases keep existing lowering. Do not
delay an effectful receiver or wrap a non-function value.

Ordinary partial applications remain restricted in both languages. Automatically wrapping
`Monad.via carrier` would change its source generalization behavior; a reusable adapter should
remain explicitly written as a function in the source.

## SML keyword spelling: implemented

Apply a consistent final AST mapping to SML keywords used as WM identifiers and field labels.
It covers declarations, references, projections, record patterns and types. For example, `fn`
normally becomes `subsetmlKeyword_fn`.

Choose one prefix for the entire supplied source batch. If any authored source contains
`subsetmlKeyword_`, append underscores until the prefix is absent from every source. This
avoids collisions with authored names and keeps imported declarations and uses consistent.
Mapping happens after checking the original names, when generating SML. It does not rewrite
strings or mutate the authored WM files. Separate cached compilation batches would need to
share this naming choice; the current translator uses one explicit source batch.

Foreign property names require their own boundary mapping when FFI lowering is implemented;
this internal identifier policy does not define JavaScript property access.

## Validation

`sh tests/carrier-lowering.sh` translates actual WM source and executes it with both MLton and
WM. It covers imported generic layouts, polymorphic empty lists, copied carriers and field aliases
at unrelated success/error types, tuple argument shape, imported datatype spelling, keyword
collisions, repeated-parameter constraints, concrete receiver types, captured partial applications
and constraints from overwritten entries. `tests/record-updates.sh` covers ordered effects and overrides.
`tests/carrier-portability/run.py` retains the reference semantic comparisons and verifies the
keyword fix independently of generic carriers.
