#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 scripts/stage-sml-compiler.py mlton "$tmp/compiler"
if ! mlton -output "$tmp/compiler/run" "$tmp/compiler/project.mlb" > "$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  exit 1
fi
"$tmp/compiler/run" check tests/accept/integer_basics.sml
mkdir "$tmp/original" "$tmp/rebuilt"
printf 'let identity = (value) => { value };\nlet message = identity("native compiler");\n' > "$tmp/tiny.wm"
bin/subsetml sml "$tmp/original" "$tmp/tiny.wm"
"$tmp/compiler/run" sml "$tmp/rebuilt" "$tmp/tiny.wm"
cmp "$tmp/original/tiny.sml" "$tmp/rebuilt/tiny.sml"
bin/subsetml sml-target mlton "$tmp/original" tests/accept/integer_basics.sml
"$tmp/compiler/run" sml-target mlton "$tmp/rebuilt" tests/accept/integer_basics.sml
for name in prelude.sml integer_basics.sml project.mlb; do
  cmp "$tmp/original/$name" "$tmp/rebuilt/$name"
done
echo 'SML target compiler bootstrap: checking, WM translation and target output parity OK'
