# SubsetML coding conventions

These are not part of the SubsetML definition (docs/spec.md). A program that ignores them is
still SubsetML and still means the same thing. They exist because translating to Workman relies
on them. `bin/subsetml wm` warns when a file breaks one, and translates it anyway.

## Case

Workman tells constructors from variables by their first letter. SML decides it from the
declarations in scope. So in SubsetML code:

- value constructors start uppercase (`Leaf`, `Node`). The current `true`,
  `false`, `nil`, `NONE` and `SOME` are already handled by the translation;
- variables, functions and record labels start lowercase;
- type constructors start lowercase (`token`, `'a tree`). They become uppercase Workman type
  names (`Token`, `Tree<a>`), and lowercase Workman type names are type variables;
- structures start uppercase. `FooBar` lives in `foo_bar.sml` (spec M1).

## Workman keywords

Do not use these as identifiers or labels. They are ordinary SML identifiers but reserved in
Workman:

```
match  record  from  import  void
```

Workman's other keywords (`let`, `rec`, `and`, `type`, `if`, `else`, `as`, `true`, `false`) are
already reserved in SML, or mean the same thing there.

## Primes

Identifiers may contain primes (`ts'`), as SML allows. Workman will accept them too; until then,
translated names with primes are not valid frontend-v3 syntax.

## Generic constructor payloads

The current translator flattens tuple constructor patterns into Workman fields. When a
constructor's declared payload is a type parameter (such as `SubsetResult.Ok` or `SOME`),
bind that payload first and unpack its tuple in the body:

```sml
case result of
  SubsetResult.Ok value => let val (first, rest) = value in first end
| SubsetResult.Err error => fallback
```

This preserves the constructor's single declared field in generated Workman. Directly
matching `SubsetResult.Ok (first, rest)` currently emits two fields and fails Workman checking.
This is a translator limitation, not a SubsetML language restriction; concrete tuple payloads
in datatype declarations continue to translate to multiple Workman fields normally.

For a concrete tuple payload, match its fields explicitly: `Err (message, offset)` rather
than `Err error`. Workman expands tuple payload types into separate constructor fields even
when the declaration uses one tuple type. The translator does not yet expand a whole-payload
variable or wildcard into those fields.

## Ignored pattern fields

The current Workman frontend can treat `_` in binder positions as a name and reject repeated
occurrences in one pattern. Compiler patterns use distinct unused names where this occurs,
for example `Operand ignoredValue :: ignoredRest`. This is a target limitation; SubsetML
wildcards remain valid and never bind values.
