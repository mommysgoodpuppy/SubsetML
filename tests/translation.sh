#!/bin/sh
# Hand-written Workman, dependency ordering, strict equality and executable SML output.
set -eu
bin=bin/subsetml
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/sml" "$tmp/rejected" "$tmp/wm"
$bin wm "$tmp/wm" tests/accept/real_functions.sml
if rg -n 'Real\.(==|!=)' "$tmp/wm/real_functions.wm"; then
  echo "FAIL: first-class real comparison left as SML"
  exit 1
fi
$bin sml "$tmp/sml" "$tmp/wm/real_functions.wm"
$bin sml "$tmp/sml" tests/wm/accept/*.wm
$bin check "$tmp/sml/z_numbers.sml" "$tmp/sml/a_use.sml"
cat > "$tmp/assert.sml" <<'SML'
val _ = if RealFunctions.same andalso RealFunctions.passed
  andalso RealFunctions.equal (2.0, 2.0) andalso RealFunctions.unequal (2.0, 3.0)
  andalso not (RealFunctions.negated (2.0, 2.0))
  andalso RealFunctions.realLeft = "outer left" andalso RealFunctions.realRight = "outer right"
  andalso AUse.after andalso Real.== (ZNumbers.width, 3.0)
  andalso Real.== (ZNumbers.fraction, ~1.5e~3)
  andalso ZNumbers.large = "1000000000000"
  andalso List.all (fn x => Real.== (x, 0.0) orelse Real.== (x, 1.0)) ZNumbers.items
  then () else OS.Process.exit OS.Process.failure
SML
printf '$(SML_LIB)/basis/basis.mlb\n%s\n%s\n%s\n%s\n%s\n' \
  "$PWD/lib/num.sml" "$tmp/sml/z_numbers.sml" "$tmp/sml/a_use.sml" "$tmp/sml/real_functions.sml" "$tmp/assert.sml" > "$tmp/test.mlb"
mlton -output "$tmp/test" "$tmp/test.mlb"
"$tmp/test"
for f in tests/wm/reject/*.wm; do
  if $bin sml "$tmp/rejected" "$f" > "$tmp/error" 2>&1; then
    echo "FAIL: translated invalid Workman: $f"
    exit 1
  fi
done
[ -z "$(ls -A "$tmp/rejected")" ] || exit 1
echo "hand-written wm translation: ok"

# Boolean evaluation order differs between the two languages.
cat > "$tmp/short_circuit.sml" <<'SML'
structure ShortCircuit = struct
  val mark = fn label => (print label; true)
  val a = false andalso mark "BAD"
  val b = true orelse mark "BAD"
  val c = true andalso mark "C"
  val d = false orelse mark "D"
end
SML
$bin roundtrip "$tmp/short_circuit.sml"
$bin wm "$tmp/wm" "$tmp/short_circuit.sml"
$bin sml "$tmp/sml" "$tmp/wm/short_circuit.wm"
for source in "$tmp/short_circuit.sml" "$tmp/sml/short_circuit.sml"; do
  printf '$(SML_LIB)/basis/basis.mlb\n%s\n' "$source" > "$tmp/boolean.mlb"
  mlton -output "$tmp/boolean" "$tmp/boolean.mlb"
  [ "$("$tmp/boolean")" = CD ]
done
cat > "$tmp/wm/lazy_boolean.wm" <<'WM'
let mark = (label) => { print(label); true };
let a = false && mark("A");
let b = true || mark("B");
WM
$bin sml "$tmp/sml" "$tmp/wm/lazy_boolean.wm"
printf '$(SML_LIB)/basis/basis.mlb\n%s\n' "$tmp/sml/lazy_boolean.sml" > "$tmp/boolean.mlb"
mlton -output "$tmp/boolean" "$tmp/boolean.mlb"
[ -z "$("$tmp/boolean")" ]
if command -v wm >/dev/null 2>&1; then
  wm run "$tmp/wm/short_circuit.wm" > "$tmp/boolean.out"
  [ "$(tr -d '\n\r' < "$tmp/boolean.out")" = CD ]
  wm run "$tmp/wm/lazy_boolean.wm" > "$tmp/boolean.out"
  [ -z "$(tr -d '\n\r' < "$tmp/boolean.out")" ]
fi
echo 'boolean evaluation order: ok'

