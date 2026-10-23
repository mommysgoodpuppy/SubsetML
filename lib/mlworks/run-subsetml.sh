#!/bin/sh
# Run a delivered compiler image; compilation/build tooling is not loaded here.
set -eu
stage_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mlworks_dir=${MLWORKS_PS2_DIR:-/home/ellie/testingstuff/mlworks-r5900}
runtime_dir=$mlworks_dir/tty-fixed-runtime
if ! test -r "$stage_dir/subsetml.img"; then
  echo "compiler image missing: $stage_dir/subsetml.img" >&2
  exit 2
fi
export LD_LIBRARY_PATH=$runtime_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
exec sh "$stage_dir/run-memory-limited.sh" "$runtime_dir/main" \
  -MLWpass MLWargs -limit 8 -load "$stage_dir/subsetml.img" MLWargs "$@"
