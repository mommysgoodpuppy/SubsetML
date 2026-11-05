#!/bin/sh
set -eu
# Staged copies get a header so nobody edits them instead of lib/.
stage() {
  { printf '// Copied from lib/%s by `make wm`. Do not edit: change the file in lib/.\n' "$1"; cat "lib/$1"; } > "$2/$1"
}
stage subset_text_host.wm "$1"
if [ -f "$1/subset_host.wm" ]; then
  stage subset_host.wm "$1"
  stage subset_host.js "$1"
fi
