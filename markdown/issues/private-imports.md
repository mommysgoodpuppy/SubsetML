# SubsetML has no private imports

Status: open, harmless for now. Recorded 2026-11-05.

## The gap

Workman imports are private unless they say `export`, which keeps a module's public surface down to
what it means to offer. SubsetML has no way to say that about an `open`: the Definition's `open`
adds to the structure's public environment, and the private form, `local open X in ... end`, is
omitted (`docs/spec.md`). So a SubsetML module can't use another's names unqualified without also
exporting them. SubsetML should have private imports too.

## Symptoms

### Basis modules re-export what they only use internally

Nine Basis modules `open SubsetOptionValue` only to write `SOME` and `NONE` unqualified, so each now
exports them: `subset_bytes`, `subset_list`, `subset_option`, `subset_result`, `subset_sml_escape`,
`subset_utf16_source`, `subset_won`, `subset_won_parser` and `subset_won_syntax`. In Workman they
translate to `export from "./subset_option_value.wm" import *;`.

Nothing depends on it. No Workman source reaches `Some` or `None` through one of them, and Workman
has both built in. Of the nine, only `subset_option` matches the SML Basis, whose `Option` exports
`SOME` and `NONE`.

### The translator can't express a private open

| Workman | Workman meaning | SML translation | SML meaning |
|---|---|---|---|
| `export from "./x.wm" import *;` | public | `open X` | public |
| `from "./x.wm" import *;` | private | `open X` | public |

So a module translated from Workman exports more in SML than it does in Workman:

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
`value` part of `Middle`. An opened name can also shadow an earlier binding of the same name in a
client that opens `Middle`.

Going the other way is not affected. SML `open` always prints as `export from ... import *;`, so a
translated SML module keeps its public environment.

## Ways to close it

Add `local open X in ... end` at structure level, and lower plain `import *` to it. It's standard
SML, so other compilers still accept the source. Like the structure alias (spec restriction M2), it
should stay as narrow as this use needs: only `open` in the `local` part, and only at the start of
a structure, rather than general `local`. `local` is one of the omitted forms, so this is a spec
change.

Until then, a module can avoid the re-export by qualifying (`SubsetOptionValue.SOME`), as
`subset_host`, `subset_string` and `subset_text` do. The translator could do the same for a plain
`import *` by rewriting its uses to qualified names, but that requires resolving every unqualified
name first.
