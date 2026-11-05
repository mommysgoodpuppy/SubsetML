#!/bin/sh
# Canonical WM import identity, aliases, private scope and SML metadata round trip.
set -eu
compiler=${SUBSETML:-bin/subsetml}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/out" "$tmp/reject" "$tmp/a" "$tmp/b"
cat > "$tmp/records.wm" <<'WM'
type Thing = | Thing<I32>;
record Box<T> = { value: T };
let make = (value) => { Thing(value) };
WM
ln -s records.wm "$tmp/alias.wm"
cat > "$tmp/middle.wm" <<'WM'
from "./records.wm" import * as Original;
let shared = Original.make(7);
WM
cat > "$tmp/entry.wm" <<'WM'
from "./middle.wm" import * as Middle;
from "./a/../records.wm" import * as Other;
from "./alias.wm" import * as Again;
let unwrap = (value: Other.Thing) => { match(value) { Again.Thing(n) => {n} } };
let box = Other.Box { value = Middle.shared };
let updated = Again.Box { ..box, value = Again.make(9) };
let answer = unwrap(updated.value) + unwrap(Middle.shared);
WM
"$compiler" sml "$tmp/out" "$tmp/entry.wm" "$tmp/alias.wm" "$tmp/middle.wm" "$tmp/records.wm"
[ "$(find "$tmp/out" -name '*.sml' | wc -l)" -eq 3 ]
"$compiler" check "$tmp/out/entry.sml"
cat > "$tmp/run.sml" <<'SML'
val _ = if Entry.answer = 16 then () else OS.Process.exit OS.Process.failure
SML
printf '$(SML_LIB)/basis/basis.mlb\n%s\n%s\n%s\n%s\n' \
  "$tmp/out/alias.sml" "$tmp/out/middle.sml" "$tmp/out/entry.sml" "$tmp/run.sml" > "$tmp/test.mlb"
mlton -output "$tmp/test" "$tmp/test.mlb"
"$tmp/test"
cat > "$tmp/a/shared.wm" <<'WM'
type Thing = | Thing<I32>;
let value = Thing(1);
WM
cp "$tmp/a/shared.wm" "$tmp/b/shared.wm"
cat > "$tmp/distinct.wm" <<'WM'
from "./a/shared.wm" import * as Left;
from "./b/shared.wm" import * as Right;
let readLeft = (v) => { match(v) { Left.Thing(n) => {n} } };
let readRight = (v) => { match(v) { Right.Thing(n) => {n} } };
let answer = readLeft(Left.value) + readRight(Right.value);
WM
"$compiler" sml "$tmp/out" "$tmp/distinct.wm" "$tmp/a/shared.wm" "$tmp/b/shared.wm"
"$compiler" check "$tmp/out/distinct.sml"
[ -f "$tmp/out/shared.sml" ] && [ -f "$tmp/out/sharedModule.sml" ]
# A record field can mention its owner's private dependency. Generated updates must
# constrain that field through the owner's exported type witness, without opening it.
cat > "$tmp/wrapper.wm" <<'WM'
from "./records.wm" import * as Private;
record Wrapped = { thing: Private.Thing };
let value = Wrapped { thing = Private.make(5) };
WM
cat > "$tmp/public.wm" <<'WM'
from "./wrapper.wm" import * as Public;
let updated = Public.Wrapped { ..Public.value, thing = Public.value.thing };
WM
"$compiler" sml "$tmp/out" "$tmp/public.wm" "$tmp/wrapper.wm" "$tmp/records.wm"
"$compiler" check "$tmp/out/public.sml"
reject() {
  text=$1
  expected=$2
  shift 2
  printf '%s\n' "$text" > "$tmp/bad.wm"
  if "$compiler" sml "$tmp/reject" "$tmp/bad.wm" "$@" > "$tmp/error" 2>&1; then
    echo "FAIL: accepted $text"; exit 1
  fi
  rg -q "$expected" "$tmp/error" || { cat "$tmp/error"; exit 1; }
  [ -z "$(ls -A "$tmp/reject")" ]
}
reject 'from "./a/shared.wm" import * as Left;
from "./b/shared.wm" import * as Right;
let read = (v) => { match(v) { Left.Thing(n) => {n} } };
let wrong = read(Right.value);' 'expected|argument' "$tmp/a/shared.wm" "$tmp/b/shared.wm"
reject 'from "./middle.wm" import * as Middle;
let leaked = Alias.make(1);' 'not explicitly imported|unbound|unknown' "$tmp/middle.wm" "$tmp/alias.wm"
reject 'from "./records.wm" import * as Different;
let leaked = Records.make(1);' 'not explicitly imported' "$tmp/records.wm"
reject 'from "./records.wm" import * as Records;
let a = 1;
from "./middle.wm" import * as Middle;' 'precede ordinary declarations' "$tmp/records.wm" "$tmp/middle.wm"
reject 'from "./records.wm" import {make};' 'header namespace imports' "$tmp/records.wm"
reject 'from "./records.wm" import * as Records;' 'not in the supplied source list'
reject 'from "./records.wm" import * as Alias;
val explicit = Alias.make 1.0;' 'expected|unbound' "$tmp/records.wm"
reject 'from "./records.wm" import * as Alias;
val explicit = Records.make 1.0;' 'expected|not explicitly imported' "$tmp/records.wm"
reject 'from "x" import * as X;' 'explicit relative'
cat > "$tmp/cycle.wm" <<'WM'
from "./bad.wm" import * as Bad;
WM
reject 'from "./cycle.wm" import * as Cycle;' 'import cycle' "$tmp/cycle.wm"
# `export from ... import *` translates to SML open, whose bindings are part of the opening module.
mkdir "$tmp/open" "$tmp/open-out" "$tmp/open-back"
printf 'type Thing = | Thing<I32>;\nlet value = 7;\n' > "$tmp/open/base.wm"
printf 'export from "./base.wm" import *;\nlet own = value + 1;\n' > "$tmp/open/middle.wm"
printf 'export from "./middle.wm" import *;\n' > "$tmp/open/forward.wm"
cat > "$tmp/open/user.wm" <<'WM'
from "./forward.wm" import * as Forward;
let total = Forward.value + Forward.own;
let thing = Forward.Thing(1);
WM
"$compiler" sml "$tmp/open-out" "$tmp/open/base.wm" "$tmp/open/middle.wm" "$tmp/open/forward.wm" "$tmp/open/user.wm"
grep -q 'open Base' "$tmp/open-out/middle.sml"
grep -q 'open Middle' "$tmp/open-out/forward.sml"
"$compiler" check "$tmp/open-out/base.sml" "$tmp/open-out/middle.sml" "$tmp/open-out/forward.sml" "$tmp/open-out/user.sml"
# And SML open prints back as the same form.
"$compiler" wm "$tmp/open-back" "$tmp/open-out/base.sml" "$tmp/open-out/middle.sml"
grep -q 'export from "./base.wm" import \*;' "$tmp/open-back/middle.wm"
if command -v wm >/dev/null 2>&1; then wm check "$tmp/open/user.wm" >/dev/null; fi
# A named clause has no SML counterpart.
reject 'export from "./records.wm" import {make};' 'SML counterpart' "$tmp/records.wm"

# `export from ... import * as` is a structure alias, reachable through every level. `val end` needs
# a backend name, so this also covers names resolved through the alias.
mkdir "$tmp/alias" "$tmp/alias-out" "$tmp/alias-back"
cat > "$tmp/alias/base.wm" <<'WM'
type Shape = | Circle<I32> | Dot;
let value: I32 = 7;
let end = 8;
let add = (a: I32, b: I32) => { a + b };
WM
cat > "$tmp/alias/os.wm" <<'WM'
export from "./base.wm" import * as Process;
let viaAlias = Process.value;
WM
printf 'export from "./os.wm" import * as OS;\n' > "$tmp/alias/sys.wm"
cat > "$tmp/alias/user.wm" <<'WM'
from "./os.wm" import * as OS;
from "./sys.wm" import * as Sys;
let total = OS.Process.add(OS.Process.value, Sys.OS.viaAlias);
let keyword = OS.Process.end;
let shape: OS.Process.Shape = OS.Process.Circle(Sys.OS.Process.value);
let radius = match(shape) { OS.Process.Circle(r) => { r }, OS.Process.Dot => { 0 } };
WM
alias_wm="$tmp/alias/base.wm $tmp/alias/os.wm $tmp/alias/sys.wm $tmp/alias/user.wm"
"$compiler" sml "$tmp/alias-out" $alias_wm
grep -q 'structure Process = Base' "$tmp/alias-out/os.sml"
grep -q 'structure OS = Os' "$tmp/alias-out/sys.sml"
alias_sml="$tmp/alias-out/base.sml $tmp/alias-out/os.sml $tmp/alias-out/sys.sml $tmp/alias-out/user.sml"
"$compiler" check $alias_sml
"$compiler" roundtrip $alias_sml
"$compiler" wm "$tmp/alias-back" $alias_sml
grep -q 'export from "./base.wm" import \* as Process;' "$tmp/alias-back/os.wm"
if command -v mlton >/dev/null 2>&1; then
  {
    printf '$(SML_LIB)/basis/basis.mlb\n'
    for f in $alias_sml; do printf '%s\n' "$f"; done
  } > "$tmp/alias-out/all.mlb"
  mlton -output "$tmp/alias-out/all" "$tmp/alias-out/all.mlb"
fi
if command -v wm >/dev/null 2>&1; then wm check "$tmp/alias/user.wm" >/dev/null; fi

# Restriction M2 keeps this from growing into general nesting.
cat > "$tmp/alias/target.sml" <<'SML'
structure Target = struct val x = 1 end
SML
reject_sml() {
  printf '%s\n' "$1" > "$tmp/alias/case.sml"
  if "$compiler" check "$tmp/alias/target.sml" "$tmp/alias/case.sml" > "$tmp/alias/error" 2>&1; then
    echo "FAIL: accepted: $1"
    exit 1
  fi
  grep -q "$2" "$tmp/alias/error" || { echo "FAIL: wrong error for: $1"; cat "$tmp/alias/error"; exit 1; }
}
reject_sml 'structure Case = struct structure P = struct end end' 'nested structures'
reject_sml 'structure Case = struct val y = 1 structure P = Target end' 'must precede'
reject_sml 'structure Case = struct structure P = Target and Q = Target end' 'expected'
reject_sml 'structure Case = struct structure P = Target.Inner end' 'structure'
reject_sml 'structure Case = struct structure P = Target structure P = Target end' 'duplicate structure alias'
reject_sml 'structure Case = struct structure P = Missing end' 'unbound structure Missing'
reject_sml 'structure Case = struct structure P = List end' 'not Basis structure List'
reject_sml 'structure P = Target' 'struct ... end'
reject_sml 'val y = let structure P = Target in 1 end' 'tructure'
# An open alone doesn't make the module's own name usable as a qualifier, in either language.
cat > "$tmp/open/qualified.wm" <<'WM'
from "./base.wm" import *;
let wrong = Base.value;
WM
if "$compiler" sml "$tmp/reject" "$tmp/open/base.wm" "$tmp/open/qualified.wm" > "$tmp/open-error" 2>&1; then
  echo 'FAIL: an open made its module name usable as a qualifier'
  exit 1
fi
echo 'WM module identities and aliases: ok'
