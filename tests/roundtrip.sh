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
$bin roundtrip src/*.sml tests/accept/*.sml && echo "wm round trips: ok" || exit 1

# wm -> sml -> wm: the generated Workman is a fixed point, text and comments included
mkdir -p "$tmp/wm" "$tmp/sml" "$tmp/wm2"
$bin wm "$tmp/wm" src/*.sml || exit 1
$bin sml "$tmp/sml" "$tmp"/wm/*.wm || exit 1
$bin wm "$tmp/wm2" "$tmp"/sml/*.sml || exit 1
changed=0
for f in "$tmp"/wm/*.wm; do
  if ! cmp -s "$f" "$tmp/wm2/$(basename "$f")"; then changed=$((changed + 1)); echo "FAIL wm fixed point: $(basename "$f")"; fi
done
[ "$changed" -eq 0 ] && echo "wm fixed point: ok" || exit 1
