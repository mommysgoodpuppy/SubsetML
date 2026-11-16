# Basis API conventions

The SubsetML Basis is inspired by the SML Basis Library, not an implementation of it. Its first
goal is portability: one source implementation that behaves the same on every target (MLton,
MLWorks, Workman/JS). This document fixes how a Basis API is shaped and when it departs from its
SML Basis counterpart, so new APIs follow rules instead of decisions made case by case.

[basis.md](basis.md) documents the individual modules; this document is the rulebook they follow.
Where an existing module breaks a rule, the module is out of date: see
[Known deviations](#known-deviations).

## 1. Start from the SML Basis

When the SML Basis has a counterpart, start from its name, meaning and argument roles, then
apply the rules below in order. Departing from SML needs one of these rules as its reason.
Anything they don't cover keeps SML's behavior.

An operation the SML Basis lacks may be added when it is portable and generally useful
(`traverse`, `filterMap`, `splitAt`, `repeat`, `via`). It follows the same rules.

## 2. Modules

- **One module per SML structure,** named `Subset` plus the structure name: `SubsetList`,
  `SubsetString`, `SubsetOs`. Workman drops the prefix (`basis/list.wm`, namespace `List`).
- **Numeric modules carry their size.** `int` and `real` have fixed sizes in SubsetML, so their
  modules are the sized SML structures, `SubsetInt32` and later `SubsetReal64`, never `Int` or
  `Real`. Workman spells the types `Int32.Int` and `Real64.Real`.
- **One name, one meaning.** A module never defines a value under a name that another module uses
  for a different operation on the same kind of data. Consumers may add new names on top of a
  Basis module (Workman's `std` does), but never redefine a Basis name.
- **Datatypes shared by several modules get their own module** when that avoids an import cycle
  (`SubsetOptionValue` for `option`).
- **Internal helpers are visible** because SubsetML has no signatures. Their names must not
  suggest a public API, and [basis.md](basis.md) lists only the stable entry points.

## 3. Names

Keep the SML name unless it is an abbreviation or reads poorly as a word; then use the spelled-out
form below. Use these replacements for every module, so one concept has one name across
the Basis.

| SML | Basis | Note |
|---|---|---|
| `rev` | `reverse` | |
| `revAppend` | `reverseAppend` | |
| `foldl` / `foldr` | `foldLeft` / `foldRight` | callback shape changes too (§5) |
| `app` | `forEach` | |
| `mapPartial` | `filterMap` | |
| `null` | `isEmpty` | |
| `hd` / `tl` | `head` / `tail` | return `Result` (§6) |
| `nth` / `sub` | `at` | |
| `getOpt` | `getOr` | |
| `valOf` | — | no unchecked unwrap; use `getOr` or a `case` |

Names SML already spells out stay: `map`, `filter`, `find`, `exists`, `all`, `partition`,
`concat`, `tabulate`, `fields`, `tokens`, `isPrefix`, `extract`, `substring`, `translate`,
`padLeft`, `explode`, `implode`, `size`, `str`.

Other naming rules:

- Predicates start with `is` (`isEmpty`, `isSome`, `isOk`, `isScalar`).
- Conversions are `fromX` / `toX`, named for the other representation (`fromNative`, `toUtf8`,
  `toCode`).
- Parsers of a whole input are `parseX` (`parseDecimal`); SML's prefix-scanning `fromString` keeps
  its name and its prefix behavior.
- A variant counting a different unit gets a distinguishing word rather than a new module
  (`padTextLeft` counts scalars, `padLeft` counts bytes).

## 4. Arguments

- **Data first.** The value being operated on is the first argument: `map (xs, f)`,
  `foldLeft (xs, initial, f)`, `fields (value, delimiter)`, `contains (characters, character)`,
  `isPrefix (value, prefix)`. For SML functions whose data comes last (`List.map f xs`,
  `String.isPrefix prefix value`), the order is reversed.
- **Tupled, not curried,** for core operations. Unary operations take their value directly.
- **Curried only for adapters** that are meant to be partially applied to build a reusable stage
  (`via transform`, `viaError inject transform`).
- When two operands play the same role, keep the SML order (`append (xs, ys)`,
  `compare (left, right)`, `zip (left, right)`).

## 5. Callbacks

- Fold callbacks take `(element, accumulator)`, for left and right folds alike.
- Paired-list callbacks take `(leftElement, rightElement)`.
- Callbacks run left to right, once per element, unless the contract says otherwise
  (`foldRight` runs right to left).
- Searches and predicates stop at the first decisive result (`find`, `exists`, `all`,
  `traverse`).
- When an operation validates its input, validation finishes before the first callback runs.
  A failed validation runs no callbacks.

## 6. Failure

Exceptions are not available, so every partial SML operation becomes total:

- **`Result` for failure.** An operation that can fail because of its input returns
  `Result (value, error)`. This replaces SML's exceptions (`Empty`, `Subscript`, `Size`,
  `Overflow` from parsing, `Fail`).
- **`option` for absence.** Return `option` only when "nothing there" is an ordinary answer, not
  a mistake by the caller: a search found nothing (`find`), a reader is at the end (`peek`,
  `next`), a variable is unset (`getEnv`). An invalid index or count is a mistake, so `at`,
  `take` and `drop` return `Result`.
- **Never forgive silently.** Don't clamp, truncate or drop input to avoid an error. `take` past
  the end is `Err OutOfBounds`; `ListPair.zip` of unequal lists is `Err UnequalLengths`. A
  forgiving variant may be added under its own name when there is a real need, documented as such.
- **No unchecked unwrap.** Nothing returns a value by assuming success.
- **Panics are for invariants,** not input. Arithmetic overflow and division by zero stay runtime
  failures as the language defines them; resource exhaustion is not reported as a `Result`.
  `SubsetProcess.panic` is for terminal invariant failures only.

## 7. Error types

- Each module that can fail declares `datatype error` with one constructor per distinct cause.
  A cause carries data only when the caller needs it to report or recover (`NonByte of int` is
  an offset).
- The same cause has the same constructor name in every module: `InvalidIndex` (negative or
  malformed index), `OutOfBounds` (valid index past the end), `InvalidCount`, `NonByte of int`,
  `EmptyList`, `UnequalLengths`.
- A module that calls another module's fallible operations wraps that error in one constructor
  named after the module, rather than flattening its causes: `StringError of SubsetString.error`,
  `UnicodeError of SubsetUnicode.error`.
- An operation whose failures differ from the rest of its module gets a separate error datatype
  named `<operation-group>_error` (`slice_error`), so the module's main `error` stays accurate.
- Errors are ordinary data with structural equality; text for them is produced at a reporting
  boundary (`errorText`), not stored in the error.

## 8. Numbers

- Counts, sizes, indices, offsets and character codes are `int` (signed 32-bit, see
  [integers.md](integers.md)). Never `real`.
- Indices are zero-based. A position equal to the length is valid for splitting, slicing and
  taking (an empty remainder), and out of bounds for element access.
- A negative count or index is `InvalidIndex` or `InvalidCount`, checked before any work or
  callback.
- Bounds checks never compute `start + count`, so extreme values can't overflow.

## 9. Text

- `string` is a byte string. Operations on it count bytes and take byte `char` callbacks.
- Unicode host text is handled by `SubsetText`, which counts Unicode scalars and passes scalar
  `int` values to callbacks. A text operation keeps the same name and contract as its byte
  counterpart, changing only the unit.
- Boundary operations validate their whole input first, so operations such as `isPrefix` return
  `Result (bool, error)` rather than `bool`.
- No locale, normalization, case folding or grapheme handling unless an operation's name says so.

## 10. Host primitives

Follow the [portability rule](basis.md#portability-rule): implement in SubsetML source, and add a
host primitive only for I/O or a target representation, with its reason recorded in
[runtime-dependencies.md](runtime-dependencies.md). An API's shape never depends on whether a
primitive implements it.

## Known deviations

Existing APIs that don't yet follow these rules. Fix them when the module is next changed, or
record here why the deviation stays.

- `SubsetChar.member (character, characters)` puts the element first, beside the data-first
  `contains (characters, character)`. It is an internal helper; it should not be public under
  that order.
- `SubsetChar.error` names its byte cause `NonByteCharacter`, where other modules use `NonByte`.
  (It carries no offset, since it describes one character.)
- `slice_error` translates to the Workman type name `Slice_error`. A name that reads well in both
  languages (`sliceError`) is preferable for new types.
- Internal helpers are exported under ordinary names (`SubsetList.validCount`, `SubsetInt32.digits`,
  `SubsetChar.isLowerChars`), which makes them look public.
