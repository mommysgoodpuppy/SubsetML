#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bin/subsetml check src/sml_char.sml
mkdir -p "$tmp/wm" "$tmp/sml"
bin/subsetml wm "$tmp/wm" src/sml_char.sml
bin/subsetml sml "$tmp/sml" "$tmp/wm/sml_char.wm"
for source in "$PWD/src/sml_char.sml" "$tmp/sml/sml_char.sml"; do
  printf '$(SML_LIB)/basis/basis.mlb\n%s\n%s\n%s\n' \
    "$PWD/lib/num.sml" "$source" "$PWD/tests/basis/compare_char.sml" > "$tmp/char.mlb"
  mlton -output "$tmp/char" "$tmp/char.mlb"
  "$tmp/char"
done
