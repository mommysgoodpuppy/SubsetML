#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
modules="src/subset_text_host.sml "$(python -c 'import json; print(" ".join(m["source"] for m in json.load(open("docs/basis-dependencies.json"))["modules"].values()))')
modules="$modules src/sml_list.sml src/sml_option.sml src/syntax.sml src/compiler_text.sml src/doc.sml"
bin/subsetml check $modules tests/basis/doc_portable.sml
bin/subsetml roundtrip $modules tests/basis/doc_portable.sml
mkdir -p "$tmp/wm" "$tmp/sml"
bin/subsetml wm "$tmp/wm" $modules tests/basis/doc_portable.sml
bin/subsetml sml "$tmp/sml" "$tmp"/wm/*.wm
for dir in "$PWD/src" "$tmp/sml"; do
  {
    printf '$(SML_LIB)/basis/basis.mlb\n'
    for module in $modules; do
      if [ "$(basename "$module")" = subset_text_host.sml ]; then
        printf '%s\n' "$PWD/lib/subset_text_host.sml"
      else printf '%s/%s\n' "$dir" "$(basename "$module")"; fi
    done
    printf '%s\n' "$PWD/tests/basis/doc_portable.sml"
  } > "$tmp/test.mlb"
  mlton -output "$tmp/test" "$tmp/test.mlb"
  actual=$("$tmp/test")
  [ "$actual" = 'portable document layout: ok' ] || { printf '%s\n' "$actual"; exit 1; }
done
if command -v wm >/dev/null 2>&1; then
  sh scripts/stage-text-host.sh "$tmp/wm"
  wm check "$tmp/wm/doc_portable.wm"
  wm run "$tmp/wm/doc_portable.wm" > "$tmp/output"
  [ "$(sed '/^$/d' "$tmp/output")" = 'portable document layout: ok' ]
fi
echo 'document layout across targets: ok'
