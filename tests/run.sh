#!/bin/sh
# Test runner, run from the repository root (make test).
#
#   tests/accept/*.sml  must be accepted, and must type-check with MLton: SubsetML is SML.
#   tests/reject/*.sml  must be rejected; the first line is `(* error: <message substring> *)`.
#   tests/parse/*.sml   printed syntax must equal the matching .expected file.
#   tests/edge/*.sml    either verdict is fine, except accepting what MLton rejects: SubsetML
#                       may be stricter than SML, never looser.

bin=bin/subsetml
pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL $1: $2"; }

for f in tests/accept/*.sml; do
  if ! out=$($bin check "$f" 2>&1); then bad "$f" "$out"
  elif ! out=$(mlb=$(mktemp --suffix=.mlb) && printf '$(SML_LIB)/basis/basis.mlb\n%s\n%s\n' \
                  "$PWD/lib/num.sml" "$PWD/$f" > "$mlb" && mlton -stop tc "$mlb" 2>&1; s=$?; rm -f "$mlb"; exit $s); then
    bad "$f" "MLton rejects it: $out"
  else ok; fi
done

for f in tests/reject/*.sml; do
  want=$(head -n 1 "$f" | sed -n 's/^(\* error: \(.*\) \*)$/\1/p')
  if [ -z "$want" ]; then bad "$f" "first line must be (* error: ... *)"; continue; fi
  if out=$($bin check "$f" 2>&1); then bad "$f" "accepted"
  else
    case "$out" in
      *"$want"*) ok ;;
      *) bad "$f" "expected '$want', got: $out" ;;
    esac
  fi
done

for f in tests/parse/*.sml; do
  exp="${f%.sml}.expected"
  if ! out=$($bin parse "$f" 2>&1); then bad "$f" "$out"
  elif [ "$out" != "$(cat "$exp")" ]; then bad "$f" "output differs:
$out"
  else ok; fi
done

for f in tests/edge/*.sml; do
  if $bin check "$f" >/dev/null 2>&1 && ! (mlb=$(mktemp --suffix=.mlb) && printf '$(SML_LIB)/basis/basis.mlb\n%s\n%s\n' \
      "$PWD/lib/num.sml" "$PWD/$f" > "$mlb" && mlton -stop tc "$mlb" >/dev/null 2>&1; s=$?; rm -f "$mlb"; exit $s); then
    bad "$f" "accepted, but MLton rejects it"
  else ok; fi
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
