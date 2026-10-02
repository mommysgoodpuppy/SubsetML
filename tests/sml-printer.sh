#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Generate expected spellings with the full native SML Basis, independently of the port.
cat > "$tmp/oracle.sml" <<'SML'
val quote = fn text => "\"" ^ String.toString text ^ "\""
val bytes = List.tabulate (256, Char.chr)
val _ = print ("structure SmlEscapeExpected = struct\nval spellings = ["
  ^ String.concatWith ", " (List.map (quote o Char.toString) bytes) ^ "]\nval all = "
  ^ quote (String.toString (String.implode bytes)) ^ "\nend\n")
SML
printf '$(SML_LIB)/basis/basis.mlb\n%s\n' "$tmp/oracle.sml" > "$tmp/oracle.mlb"
mlton -output "$tmp/oracle" "$tmp/oracle.mlb"
"$tmp/oracle" > "$tmp/sml_escape_expected.sml"
modules=$(python scripts/basis-sources.py)
modules="$modules src/sml_list.sml src/sml_option.sml src/syntax.sml src/compiler_text.sml src/lexer.sml src/parser.sml src/print.sml src/doc.sml src/sml_print.sml"
fixtures="$tmp/sml_escape_expected.sml tests/basis/sml_printer.sml"
bin/subsetml check $modules $fixtures
bin/subsetml roundtrip $modules $fixtures
mkdir -p "$tmp/wm" "$tmp/sml"
bin/subsetml wm "$tmp/wm" $modules $fixtures
bin/subsetml sml "$tmp/sml" "$tmp"/wm/*.wm
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
      else printf '%s/%s\n' "$dir" "$(basename "$module")"; fi
    done
    printf '%s\n' "$tmp/sml_escape_expected.sml" "$PWD/tests/basis/sml_printer.sml"
  } > "$tmp/test.mlb"
  mlton -output "$tmp/test" "$tmp/test.mlb"
  actual=$("$tmp/test")
  [ "$actual" = 'portable SML printer: ok' ] || { printf '%s\n' "$actual"; exit 1; }
done
if command -v wm >/dev/null 2>&1; then
  sh scripts/stage-text-host.sh "$tmp/wm"
  wm check "$tmp/wm/sml_printer.wm"
  wm run "$tmp/wm/sml_printer.wm" > "$tmp/output"
  [ "$(sed '/^$/d' "$tmp/output")" = 'portable SML printer: ok' ]
  cat > "$tmp/wm/foreign_escape.wm" <<'WM'
from "./subset_sml_escape.wm" import * as SubsetSmlEscape;
from "./subset_result.wm" import * as SubsetResult;
let checked = SubsetSmlEscape.escapeByte('\u0100') == SubsetResult.Err(SubsetSmlEscape.NonByte(0))
  && SubsetSmlEscape.escapeBytes(['a', '\u0100']) == SubsetResult.Err(SubsetSmlEscape.NonByte(1))
  && SubsetSmlEscape.escapeString("a\u{1f600}") == SubsetResult.Err(SubsetSmlEscape.NonByte(1));
let _ = if (checked) { print("foreign escaping rejected"); } else { print("FAILED"); };
WM
  wm check "$tmp/wm/foreign_escape.wm"
  wm run "$tmp/wm/foreign_escape.wm" > "$tmp/output"
  [ "$(sed '/^$/d' "$tmp/output")" = 'foreign escaping rejected' ]
fi
echo 'SML printer across targets: all 256 byte spellings ok'
