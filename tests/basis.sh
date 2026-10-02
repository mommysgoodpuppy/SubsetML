#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
modules="src/sml_list.sml src/sml_list_pair.sml src/sml_option.sml"
bin/subsetml check $modules tests/basis/portable_basis.sml
printf '$(SML_LIB)/basis/basis.mlb\n%s\n%s\n%s\n%s\n' \
  "$PWD/src/sml_list.sml" "$PWD/src/sml_list_pair.sml" "$PWD/src/sml_option.sml" "$PWD/tests/basis/compare.sml" > "$tmp/compare.mlb"
mlton -output "$tmp/compare" "$tmp/compare.mlb"
"$tmp/compare"
mkdir -p "$tmp/wm" "$tmp/sml"
bin/subsetml wm "$tmp/wm" $modules tests/basis/portable_basis.sml
bin/subsetml sml "$tmp/sml" "$tmp"/wm/*.wm
printf '$(SML_LIB)/basis/basis.mlb\n%s\n%s\n%s\n%s\n' \
  "$tmp/sml/sml_list.sml" "$tmp/sml/sml_list_pair.sml" "$tmp/sml/sml_option.sml" "$tmp/sml/portable_basis.sml" > "$tmp/portable.mlb"
mlton -output "$tmp/portable" "$tmp/portable.mlb"
[ "$("$tmp/portable")" = "portable basis: ok" ]
if command -v wm >/dev/null 2>&1; then
  wm check "$tmp/wm/portable_basis.wm"
  [ "$(wm run "$tmp/wm/portable_basis.wm")" = "portable basis: ok" ]
  echo "Workman portable Basis: ok"
else
  echo "Workman portable Basis: skipped (wm unavailable)"
fi
