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
reject 'from "./records.wm" import *;' 'preceding namespace import' "$tmp/records.wm"
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
echo 'WM module identities and aliases: ok'
