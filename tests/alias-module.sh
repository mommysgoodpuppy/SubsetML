#!/bin/sh
# An alias module, `structure A = B` at top level, re-exports B under A, with B's types.
set -eu
bin=bin/subsetml
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/numbers.sml" <<'SML'
structure Numbers = struct
  datatype sign = Negative | Positive
  val signOf = fn n : int => if n < 0 then Negative else Positive
end
SML
cat > "$tmp/num.sml" <<'SML'
(* @subsetml
from "./numbers.sml" import * as Numbers;
*)
structure Num = Numbers
SML
cat > "$tmp/main.sml" <<'SML'
(* @subsetml
from "./num.sml" import * as Num;
from "./numbers.sml" import * as Numbers;
*)
structure Main = struct
  val code = fn n => case Num.signOf n of Numbers.Negative => 0 | Num.Positive => 1
end
SML
$bin check "$tmp/main.sml" > /dev/null
mkdir "$tmp/wm"
$bin wm "$tmp/wm" "$tmp/numbers.sml" "$tmp/num.sml" "$tmp/main.sml"
grep -q 'export from "./numbers.wm" import \*;' "$tmp/wm/num.wm"
# Only an unqualified program structure can be aliased.
printf 'structure Bad = OS.Process\n' > "$tmp/bad.sml"
if $bin check "$tmp/bad.sml" > "$tmp/bad.out" 2>&1; then echo "FAIL: accepted a qualified alias target"; exit 1; fi
grep -q 'alias structure expressions' "$tmp/bad.out"
echo "alias modules: check, WM translation and qualified-target rejection passed"
