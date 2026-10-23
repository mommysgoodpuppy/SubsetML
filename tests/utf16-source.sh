#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
modules=$(python scripts/basis-sources.py)
test=tests/basis/utf16_source.sml
bin/subsetml check $modules "$test"
bin/subsetml roundtrip $modules "$test"
mkdir -p "$tmp/wm" "$tmp/sml"
bin/subsetml wm "$tmp/wm" $modules "$test"
bin/subsetml sml "$tmp/sml" "$tmp"/wm/*.wm
for dir in "$PWD/src" "$tmp/sml"; do
  {
    printf '$(SML_LIB)/basis/basis.mlb\n'
    for module in $modules; do
      case "$(basename "$module")" in
        subset_host.sml) printf '%s\n' "$PWD/lib/subset_host.sml" ;;
        subset_text_host.sml) printf '%s\n' "$PWD/lib/subset_text_host.sml" ;;
        *) printf '%s/%s\n' "$dir" "$(basename "$module")" ;;
      esac
    done
    printf '%s\n' "$PWD/$test"
  } > "$tmp/test.mlb"
  mlton -output "$tmp/test" "$tmp/test.mlb"
  [ "$("$tmp/test")" = 'UTF-16 source contracts: ok' ]
done
if command -v wm >/dev/null 2>&1; then
  sh scripts/stage-text-host.sh "$tmp/wm"
  wm check "$tmp/wm/utf16_source.wm"
  wm run "$tmp/wm/utf16_source.wm" > "$tmp/output"
  [ "$(sed '/^$/d' "$tmp/output")" = 'UTF-16 source contracts: ok' ]
  # JS strings expose UTF-16 units, including lone surrogates. The native adapter's
  # byte-string contract is tested above rather than pretending both storage formats match.
  cat > "$tmp/wm/js_units.wm" <<'WM'
from "./subset_utf16_source.wm" import * as Source;
from "./subset_result.wm" import * as Result;
from js.global("String") import unsafe { fromCharCode: Number -> String };
let check = (units, expected) => {
  match(Source.fromNativeUnits(units)) {
    Result.Err(_) => {false},
    Result.Ok(source) => {Source.toUnits(source) == expected}
  }
};
let main = () => {
  if (check(fromCharCode(55296), [55296]) && check(fromCharCode(56320), [56320]) && check("\u{1F600}", [55357, 56832])) {
    print("JS UTF-16 units: ok")
  } else {Panic("JS UTF-16 units failed")}
};
WM
  wm run "$tmp/wm/js_units.wm" > "$tmp/output"
  [ "$(sed '/^$/d' "$tmp/output")" = 'JS UTF-16 units: ok' ]
fi
echo 'portable UTF-16 source: ok'
