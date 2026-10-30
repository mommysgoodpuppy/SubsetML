#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
runner=""
if command -v wm >/dev/null 2>&1; then
  make wm
  if ! wm compile src/main.wm "$tmp/compiler.mjs" > "$tmp/compile.log" 2>&1; then
    cat "$tmp/compile.log" >&2
    exit 1
  fi
  runner="$tmp/compiler.mjs"
fi
python tests/module_loading.py "$tmp" "$runner"
