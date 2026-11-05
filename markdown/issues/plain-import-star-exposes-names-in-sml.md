# Plain `import *` exposes names on the SML side

Status: open, accepted edge case for now. Recorded 2026-11-05.

## The mismatch

Workman has two forms of open import:

| Workman | Workman meaning | SML translation | SML meaning |
|---|---|---|---|
| `export from "./x.wm" import *;` | public | `open X` | public |
| `from "./x.wm" import *;` | private | `open X` | public |

The first pair agrees. The second doesn't: the exact SML counterpart of a private open is
`local open X in ... end`, and SubsetML omits `local`, so the translator emits a plain `open`.

## What goes wrong

A module translated from Workman to SML exports more than it does in Workman:

```
// base.wm
let value = 7;

// middle.wm
from "./base.wm" import *;
let own = value + 1;

// user.wm
from "./middle.wm" import * as Middle;
let v = Middle.value;
```

`wm check user.wm` rejects `Middle.value`. The translated SML accepts it, because `open Base` made
`value` part of `Middle`. A program valid in Workman keeps its meaning unless a name in `Middle`'s
clients now resolves differently: an opened name can also shadow an earlier binding of the same
name in a client that opens `Middle`.

Going the other way is not affected. SML `open` always prints as `export from ... import *;`, so a
translated SML module keeps its public environment.

## Ways to close it

- Support `local` in SubsetML, at least the `local open X in ... end` form, and lower plain
  `import *` to it.
- Rewrite the private open's uses to qualified names (`X.value`) during translation and emit no
  `open`. This needs no language change but requires resolving every unqualified name first.
- Reject plain `import *` in the translator and require `export from` or `import * as`. Simple, but
  it makes valid Workman untranslatable.
