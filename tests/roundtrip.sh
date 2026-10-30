#!/bin/sh
# Round trips, run from the repository root: reprinting a file must not change its syntax tree.
#   sml: parse -> SmlPrint -> parse
bin=bin/subsetml
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
for f in src/*.sml tests/accept/*.sml; do
  b=$(basename "$f")
  if ! $bin fmt "$f" > "$tmp/$b" 2>&1; then fail=$((fail + 1)); echo "FAIL fmt $f"; continue; fi
  if [ "$($bin parse "$f")" = "$($bin parse "$tmp/$b" 2>&1)" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL sml round trip $f: $($bin parse "$tmp/$b" 2>&1 | head -2)"; fi
done
echo "round trips: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1

# sml -> wm -> sml: each file's declarations survive the translation (up to Normalize)
set --
# The compiler's integer code translates as I32.
$bin roundtrip src/subset_option_value.sml src/subset_result.sml src/subset_list.sml || { echo "FAIL: integer compiler module round trip"; exit 1; }
for f in tests/accept/*.sml; do
  case "$f" in
    tests/accept/overload-unresolved.sml|tests/accept/integer_basics.sml)
      # A numeric operation fixed only by SML's int default would become Number in Workman.
      if $bin roundtrip "$f" > "$tmp/unsupported" 2>&1; then
        echo "FAIL: accepted a defaulted numeric operation: $f"; exit 1
      fi
      rg -q 'only a default decides' "$tmp/unsupported" || exit 1
      ;;
    tests/accept/core.sml|tests/accept/types.sml)
      # These checker fixtures intentionally contain declarations outside the WM profile.
      if $bin roundtrip "$f" > "$tmp/unsupported" 2>&1; then
        echo "FAIL: accepted unsupported WM translation $f"; exit 1
      fi
      rg -q 'embedded SML declarations are not supported' "$tmp/unsupported" || exit 1
      ;;
    *) set -- "$@" "$f" ;;
  esac
done
$bin roundtrip "$@" && echo "wm round trips: ok (unsupported declaration fixtures rejected)" || exit 1

# wm -> sml -> wm: the generated Workman is a fixed point, text and comments included
mkdir -p "$tmp/wm" "$tmp/sml" "$tmp/wm2"
# Record source fixtures gain native constructor helpers on reverse translation;
# syntax/semantic roundtrip above covers them, but they are not a text fixed point.
$bin wm "$tmp/wm" tests/accept/real_functions.sml tests/accept/structures.sml || exit 1
$bin sml "$tmp/sml" "$tmp"/wm/*.wm || exit 1
$bin wm "$tmp/wm2" "$tmp"/sml/*.sml || exit 1
changed=0
for f in "$tmp"/wm/*.wm; do
  if ! cmp -s "$f" "$tmp/wm2/$(basename "$f")"; then changed=$((changed + 1)); echo "FAIL wm fixed point: $(basename "$f")"; fi
done
[ "$changed" -eq 0 ] && echo "wm fixed point: ok" || exit 1
