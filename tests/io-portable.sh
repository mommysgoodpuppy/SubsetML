#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
modules=$(python scripts/basis-sources.py)
fixture=tests/basis/io_portable.sml
python - "$tmp/input-å.bin" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(bytes(range(256)))
PY
bin/subsetml check $modules "$fixture"
{
  printf '$(SML_LIB)/basis/basis.mlb\n'
  for module in $modules; do
    case "$(basename "$module")" in
      subset_text_host.sml) printf '%s\n' "$PWD/lib/subset_text_host.sml" ;;
      subset_host.sml) printf '%s\n' "$PWD/lib/subset_host.sml" ;;
      *) printf '%s/%s\n' "$PWD" "$module" ;;
    esac
  done
  printf '%s/%s\n' "$PWD" "$fixture"
} > "$tmp/test.mlb"
mlton -output "$tmp/test" "$tmp/test.mlb"
"$tmp/test" "$tmp/input-å.bin" "$tmp/native.bin" "$tmp/missing.bin" > "$tmp/native.out" 2> "$tmp/native.err"
mkdir -p "$tmp/wm"
bin/subsetml wm "$tmp/wm" $modules "$fixture"
sh scripts/stage-text-host.sh "$tmp/wm"
if command -v wm >/dev/null 2>&1; then
  wm check "$tmp/wm/io_portable.wm"
  wm run "$tmp/wm/io_portable.wm" -- "$tmp/input-å.bin" "$tmp/workman.bin" "$tmp/missing.bin" > "$tmp/workman.out" 2> "$tmp/workman.err"
  # Source validation must reject foreign data before truncating an existing file.
  cat > "$tmp/wm/foreign_io.wm" <<'WM'
from "./subset_io.wm" import * as Io;
from "./subset_result.wm" import * as R;
from "./subset_process.wm" import * as Process;
let _ = match(Process.arguments()) {
  R.Ok([input, output, missing]) => {
    let checked = match(Io.writeFile(['\u0100'], output)) {
      R.Err(Io.NonByte(offset)) => { offset == 0 },
      _ => { false }
    };
    Process.exit(if (checked) { Process.success } else { Process.failure })
  },
  _ => { Process.exit(Process.failure) }
};
WM
  wm run "$tmp/wm/foreign_io.wm" -- "$tmp/input-å.bin" "$tmp/workman.bin" "$tmp/missing.bin" > "$tmp/foreign.out" 2> "$tmp/foreign.err"
fi
python - "$tmp" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
expected = bytes(range(256))
for target in ['native', 'workman']:
    if (root / (target + '.bin')).exists():
        for suffix in ['.bin', '.out', '.err']:
            assert (root / (target + suffix)).read_bytes() == expected, target + suffix
PY
echo 'whole-file byte I/O across targets: ok'
