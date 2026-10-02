#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Independent reference spellings for the printer's byte-only Workman literal profile.
python - "$tmp/wm_escape_expected.sml" <<'PYREF'
from pathlib import Path
import sys
def escape(byte, quote):
    if byte in (10, 9, 13): return {10:r'\n',9:r'\t',13:r'\r'}[byte]
    if byte==92: return r'\\'
    if byte==quote: return '\\'+chr(byte)
    if 32<=byte<127: return chr(byte)
    return '\\u00'+format(byte,'02x')
def literal(text): return '"'+text.replace('\\','\\\\').replace('"','\\"')+'"'
Path(sys.argv[1]).write_text('structure WmEscapeExpected = struct\nval characters = ['
    + ', '.join(literal(escape(byte,39)) for byte in range(256))
    + ']\nval string = '+literal(''.join(escape(byte,34) for byte in range(256)))+'\nend\n')
PYREF
modules=$(python scripts/basis-sources.py)
modules="$modules src/sml_list.sml src/sml_option.sml src/syntax.sml src/compiler_text.sml src/lexer.sml src/parser.sml src/doc.sml src/sml_print.sml src/wm_print.sml src/wm_lexer.sml"
fixtures="$tmp/wm_escape_expected.sml tests/basis/wm_printer.sml"
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
    printf '%s\n' "$tmp/wm_escape_expected.sml" "$PWD/tests/basis/wm_printer.sml"
  } > "$tmp/test.mlb"
  mlton -output "$tmp/test" "$tmp/test.mlb"
  actual=$("$tmp/test")
  [ "$actual" = 'portable Workman printer: ok' ] || { printf '%s\n' "$actual"; exit 1; }
done
if command -v wm >/dev/null 2>&1; then
  sh scripts/stage-text-host.sh "$tmp/wm"
  wm check "$tmp/wm/wm_printer.wm"
  wm run "$tmp/wm/wm_printer.wm" > "$tmp/output"
  [ "$(sed '/^$/d' "$tmp/output")" = 'portable Workman printer: ok' ]

fi
echo 'Workman printer across targets: all 256 byte spellings ok'
