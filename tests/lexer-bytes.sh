#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
modules="src/subset_text_host.sml "$(python -c 'import json; print(" ".join(m["source"] for m in json.load(open("docs/basis-dependencies.json"))["modules"].values()))')
modules="$modules src/sml_list.sml src/sml_option.sml src/syntax.sml src/compiler_text.sml src/lexer.sml src/parser.sml src/wm_lexer.sml"
bin/subsetml check $modules tests/basis/lexer_bytes.sml
bin/subsetml roundtrip $modules tests/basis/lexer_bytes.sml
mkdir -p "$tmp/wm" "$tmp/sml"
bin/subsetml wm "$tmp/wm" $modules tests/basis/lexer_bytes.sml
bin/subsetml sml "$tmp/sml" "$tmp"/wm/*.wm
for dir in "$PWD/src" "$tmp/sml"; do
  {
    printf '$(SML_LIB)/basis/basis.mlb\n'
    for module in $modules; do
      if [ "$(basename "$module")" = subset_text_host.sml ]; then
        printf '%s\n' "$PWD/lib/subset_text_host.sml"
      else printf '%s/%s\n' "$dir" "$(basename "$module")"; fi
    done
    printf '%s\n' "$PWD/tests/basis/lexer_bytes.sml"
  } > "$tmp/test.mlb"
  mlton -output "$tmp/test" "$tmp/test.mlb"
  actual=$("$tmp/test")
  [ "$actual" = 'byte lexers and parser: ok' ] || { printf '%s\n' "$actual"; exit 1; }
done
if command -v wm >/dev/null 2>&1; then
  sh scripts/stage-text-host.sh "$tmp/wm"
  wm check "$tmp/wm/lexer_bytes.wm"
  wm run "$tmp/wm/lexer_bytes.wm" > "$tmp/output"
  actual=$(sed '/^$/d' "$tmp/output")
  [ "$actual" = 'byte lexers and parser: ok' ] || { printf '%s\n' "$actual"; exit 1; }
  cat > "$tmp/wm/foreign_source.wm" <<'WM'
from "./lexer.wm" import * as Lexer;
from "./parser.wm" import * as Parser;
from "./wm_lexer.wm" import * as WmLexer;
let sml = match(Lexer.lex("a\u0100")) {
  Lexer.LexError(_, pos) => { pos == 1 },
  Lexer.Tokens(tokens, comments) => { false }
};
let wm = match(WmLexer.lex("a\u{1f600}")) {
  WmLexer.LexError(_, pos) => { pos == 1 },
  WmLexer.Tokens(tokens, comments) => { false }
};
let parser = match(Parser.parse("a\u0100")) {
  Parser.ParseError(_, pos) => { pos == 1 },
  Parser.Program(program, comments) => { false }
};
let _ = if (sml && wm && parser) { print("foreign source rejected"); } else { print("FAILED"); };
WM
  wm check "$tmp/wm/foreign_source.wm"
  wm run "$tmp/wm/foreign_source.wm" > "$tmp/output"
  [ "$(sed '/^$/d' "$tmp/output")" = 'foreign source rejected' ]
fi
echo 'cached byte lexer/parser execution: ok'
