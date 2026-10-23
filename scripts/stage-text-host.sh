#!/bin/sh
set -eu
cp lib/subset_text_host.wm "$1/subset_text_host.wm"
if [ -f "$1/subset_host.wm" ]; then
  cp lib/subset_host.wm lib/subset_host.js "$1/"
fi
