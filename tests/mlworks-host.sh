#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 scripts/stage-mlworks-host.py "$tmp"
printf '"%s/project.mlb"\n"%s/driver.sml"\n' "$tmp" "$tmp" > "$tmp/run.mlb"
mlton -output "$tmp/run" "$tmp/run.mlb"
(cd "$tmp" && ./run > stdout.log 2> stderr.log)
python3 - "$tmp" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
assert (root / 'stdout.log').read_bytes() == b'MLWORKS_HOST_PROBE_OK\nSTDOUT_BYTES_BEGIN\n' + bytes(range(256)) + b'\nSTDOUT_BYTES_END\n'
assert (root / 'stderr.log').read_bytes() == b'STDERR_BYTES_BEGIN\n' + bytes(range(256)) + b'\nSTDERR_BYTES_END\nMLWORKS_HOST_STDERR_OK\n'
assert (root / 'stream-bytes.bin').read_bytes() == bytes(range(256))
assert not (root / 'probe-dir').exists()
PY
echo 'MLWorks host contract and WM -> SubsetML workflow: desktop OK'
