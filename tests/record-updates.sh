#!/bin/sh
# Named layouts, generic/imported records, and update evaluation/override order.
set -eu
compiler=${SUBSETML:-bin/subsetml}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/sml" "$tmp/reject"
cat > "$tmp/records.wm" <<'WM'
record Point = { x: Number, y: Number };
record Box<T> = { value: T };
WM
cat > "$tmp/updates.wm" <<'WM'
from "./records.wm" import * as Records;
let mark = (label, value) => { print(label); value };
let base = (label) => { print(label); Records.Point { x = 1, y = 2 } };
let main = () => {
  let subsetmlRecord0_0 = "authored";
  let point = Records.Point {
    x = mark("A", 10), ..base("B"), y = mark("C", 20), ..base("D")
  };
  let box = Records.Box { value = "old" };
  let updated = Records.Box { ..box, value = "new" };
  print(if (point.x == 1 && point.y == 2 && updated.value == "new") {"OK"} else {"BAD"});
};
WM
"$compiler" sml "$tmp/sml" "$tmp/updates.wm" "$tmp/records.wm"
cat > "$tmp/run.sml" <<'SML'
val _ = Updates.main ()
SML
printf '$(SML_LIB)/basis/basis.mlb\n%s\n%s\n%s\n%s\n' \
  "$PWD/lib/num.sml" "$tmp/sml/records.sml" "$tmp/sml/updates.sml" "$tmp/run.sml" > "$tmp/test.mlb"
mlton -output "$tmp/test" "$tmp/test.mlb"
[ "$("$tmp/test")" = ABCDOK ]
if command -v wm >/dev/null 2>&1; then
  wm run "$tmp/updates.wm" > "$tmp/result"
  [ "$(tr -d '\r\n' < "$tmp/result")" = ABCDOK ]
fi
reject() {
  printf '%s\n' 'from "./records.wm" import * as Records;' "$1" > "$tmp/bad.wm"
  if "$compiler" sml "$tmp/reject" "$tmp/records.wm" "$tmp/bad.wm" > "$tmp/error" 2>&1; then
    echo "FAIL: accepted $1"; exit 1
  fi
  if ! rg -q "$2" "$tmp/error"; then cat "$tmp/error"; exit 1; fi
  [ -z "$(ls -A "$tmp/reject")" ]
}
reject 'let bad = () => { record Local = { x: Number }; Local { x = 1 } };' 'record layout declarations must be top-level'
reject 'let bad = .{..value, x = 3};' 'record updates must name their record type'
reject 'let bad = Missing { x = 3 };' 'unknown record layout'
reject 'let bad = Records.Point { x = 3 };' 'missing record field y'
reject 'let bad = Records.Point { x = 3, x = 4, y = 2 };' 'duplicate record field x'
reject 'let bad = Records.Point { x = 3, z = 4 };' 'has no field z'
reject 'let bad = Records.Point { x = "wrong", ..Records.Point { x = 1, y = 2 } };' 'expected real|type annotation'
reject 'let bad = Records.Box { ..Records.Box { value = "text" }, value = true };' 'argument|expected'
echo 'named record updates: ok'
