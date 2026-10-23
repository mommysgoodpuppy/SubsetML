#!/bin/sh
# WON Basis modules: the same probe source runs natively and as generated Workman.
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
modules=$(python scripts/basis-sources.py)
fixtures="tests/basis/won_probe.sml tests/basis/won_main.sml"
bin/subsetml check $modules $fixtures
bin/subsetml roundtrip $modules $fixtures
mkdir -p "$tmp/wm"
bin/subsetml wm "$tmp/wm" $modules $fixtures
{
  printf '$(SML_LIB)/basis/basis.mlb\n'
  for module in $modules; do
    case "$(basename "$module")" in
      subset_host.sml) printf '%s\n' "$PWD/lib/subset_host.sml" ;;
      subset_text_host.sml) printf '%s\n' "$PWD/lib/subset_text_host.sml" ;;
      *) printf '%s\n' "$PWD/$module" ;;
    esac
  done
  for fixture in $fixtures; do printf '%s\n' "$PWD/$fixture"; done
} > "$tmp/test.mlb"
mlton -output "$tmp/native" "$tmp/test.mlb"
"$tmp/native" > "$tmp/native-output"
grep -qx 'ok ok' "$tmp/native-output" || { cat "$tmp/native-output"; exit 1; }
if command -v wm >/dev/null 2>&1; then
  sh scripts/stage-text-host.sh "$tmp/wm"
  wm run "$tmp/wm/won_main.wm" > "$tmp/wm-output"
  cmp "$tmp/native-output" "$tmp/wm-output"
fi
echo 'WON Basis across targets: ok'
