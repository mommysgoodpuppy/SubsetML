#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
modules="src/subset_text_host.sml src/subset_result.sml src/subset_option.sml src/subset_list.sml src/subset_list_pair.sml src/subset_order.sml src/subset_char.sml src/subset_bytes.sml src/subset_unicode.sml src/subset_utf8.sml src/subset_utf16.sml src/subset_string.sml src/subset_source.sml src/subset_sml_escape.sml"
bin/subsetml check $modules tests/basis/custom_basis.sml tests/basis/custom_char_portable.sml tests/basis/custom_order_portable.sml
python tests/basis/dependencies.py
bin/subsetml roundtrip $modules tests/basis/custom_basis.sml tests/basis/custom_char_portable.sml tests/basis/custom_order_portable.sml
mkdir -p "$tmp/wm" "$tmp/sml"
bin/subsetml wm "$tmp/wm" $modules tests/basis/custom_basis.sml tests/basis/custom_char_portable.sml tests/basis/custom_order_portable.sml
bin/subsetml sml "$tmp/sml" "$tmp"/wm/*.wm
expected='visit a
visit b
visit c
try a
try stop
custom basis: ok
custom ordering: ok'
for dir in "$PWD/src" "$tmp/sml"; do
  {
    printf '$(SML_LIB)/basis/basis.mlb\n'
    for module in $modules; do
      if [ "$(basename "$module")" = subset_text_host.sml ]; then
        printf '%s\n' "$PWD/lib/subset_text_host.sml"
        continue
      fi
      printf '%s/%s\n' "$dir" "$(basename "$module")"; done
    printf '%s\n' "$PWD/tests/basis/custom_callbacks.sml" "$PWD/tests/basis/custom_char_compare.sml" "$PWD/tests/basis/custom_order_compare.sml"
  } > "$tmp/callbacks.mlb"
  mlton -output "$tmp/callbacks" "$tmp/callbacks.mlb"
  "$tmp/callbacks"
done
{
  printf '$(SML_LIB)/basis/basis.mlb\n'
  for module in $modules; do
      if [ "$(basename "$module")" = subset_text_host.sml ]; then
        printf '%s\n' "$PWD/lib/subset_text_host.sml"
        continue
      fi
      printf '%s/%s\n' "$tmp/sml" "$(basename "$module")"; done
  printf '%s\n' "$tmp/sml/custom_basis.sml" "$tmp/sml/custom_order_portable.sml"
} > "$tmp/custom.mlb"
mlton -output "$tmp/custom" "$tmp/custom.mlb"
[ "$("$tmp/custom")" = "$expected" ]
if command -v wm >/dev/null 2>&1; then
  sh scripts/stage-text-host.sh "$tmp/wm"
  wm check "$tmp/wm/custom_basis.wm"
  # Workman's bootstrap print adds a newline; SML's print writes the supplied bytes.
  # Compare complete trace tokens, ignoring only the resulting empty lines.
  wm run "$tmp/wm/custom_basis.wm" > "$tmp/wm-output"
  wm check "$tmp/wm/custom_order_portable.wm"
  wm run "$tmp/wm/custom_order_portable.wm" >> "$tmp/wm-output"
  actual=$(sed '/^$/d' "$tmp/wm-output")
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL custom Workman output:\n%s\n' "$actual"
    exit 1
  fi
  wm check "$tmp/wm/custom_char_portable.wm"
  wm run "$tmp/wm/custom_char_portable.wm" > "$tmp/char-output"
  [ "$(sed '/^$/d' "$tmp/char-output")" = 'custom portable characters: ok' ]
  # A foreign Workman character can be outside SubsetML's byte-character domain.
  cat > "$tmp/wm/foreign_char.wm" <<'WM'
from "./subset_char.wm" import * as SubsetChar;
from "./subset_result.wm" import * as SubsetResult;
from "./subset_bytes.wm" import * as SubsetBytes;
from "./subset_unicode.wm" import * as SubsetUnicode;
from "./subset_utf8.wm" import * as SubsetUtf8;
from "./subset_utf16.wm" import * as SubsetUtf16;
from "./subset_string.wm" import * as SubsetString;
let foreign = '\u0100';
let checked = SubsetString.fromNative("a\u0100") == SubsetResult.Err(SubsetString.NonByte(1))
  && SubsetString.toNative(['a', foreign]) == SubsetResult.Err(SubsetString.NonByte(1))
  && SubsetString.fromNative("a\u{1f600}") == SubsetResult.Err(SubsetString.NonByte(1))
  && SubsetChar.toCode(foreign) == SubsetResult.Err(SubsetChar.NonByteCharacter)
  && SubsetBytes.reader([foreign]) == SubsetResult.Err(SubsetBytes.NonByte(0))
  && SubsetUtf8.decode(['a', foreign]) == SubsetResult.Err(SubsetUnicode.Error(SubsetUnicode.InvalidByte, 1))
  && SubsetUtf16.decode(['a', foreign], SubsetUtf16.LittleEndian)
    == SubsetResult.Err(SubsetUnicode.Error(SubsetUnicode.InvalidByte, 1));
let _ = if (checked) { print("foreign character rejected"); } else { print("FAILED"); };
WM
  wm check "$tmp/wm/foreign_char.wm"
  wm run "$tmp/wm/foreign_char.wm" > "$tmp/foreign-char-output"
  [ "$(sed '/^$/d' "$tmp/foreign-char-output")" = 'foreign character rejected' ]
  echo 'Workman custom Basis: ok'
else
  echo 'Workman custom Basis: skipped (wm unavailable)'
fi
