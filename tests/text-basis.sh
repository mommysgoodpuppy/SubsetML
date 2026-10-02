#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
modules=$(python scripts/basis-sources.py)
python tests/basis/text_vectors.py > "$tmp/text_vectors.sml"
bin/subsetml check $modules tests/basis/text_basis.sml "$tmp/text_vectors.sml"
bin/subsetml roundtrip $modules tests/basis/text_basis.sml "$tmp/text_vectors.sml"
mkdir -p "$tmp/wm" "$tmp/sml"
bin/subsetml wm "$tmp/wm" $modules tests/basis/text_basis.sml "$tmp/text_vectors.sml"
bin/subsetml sml "$tmp/sml" "$tmp"/wm/*.wm
expected='text contracts: ok
text reference vectors: ok'
for dir in "$PWD/src" "$tmp/sml"; do
  {
    printf '$(SML_LIB)/basis/basis.mlb\n'
    for module in $modules; do
      if [ "$(basename "$module")" = subset_host.sml ]; then
        printf '%s\n' "$PWD/lib/subset_host.sml"
        continue
      fi
      if [ "$(basename "$module")" = subset_text_host.sml ]; then
        printf '%s\n' "$PWD/lib/subset_text_host.sml"
        continue
      fi
      printf '%s/%s\n' "$dir" "$(basename "$module")"; done
    printf '%s\n' "$PWD/tests/basis/text_basis.sml" "$tmp/text_vectors.sml"
  } > "$tmp/test.mlb"
  mlton -output "$tmp/text-test" "$tmp/test.mlb"
  [ "$("$tmp/text-test")" = "$expected" ]
done
if command -v wm >/dev/null 2>&1; then
  sh scripts/stage-text-host.sh "$tmp/wm"
  wm check "$tmp/wm/text_basis.wm"
  wm check "$tmp/wm/text_vectors.wm"
  wm run "$tmp/wm/text_basis.wm" > "$tmp/output"
  wm run "$tmp/wm/text_vectors.wm" >> "$tmp/output"
  [ "$(sed '/^$/d' "$tmp/output")" = "$expected" ]
fi
echo 'portable text codecs/readers: ok'
