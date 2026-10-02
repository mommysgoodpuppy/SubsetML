#!/bin/sh
# Keeps src/*.wm in sync with src/*.sml: whenever a source changes, rebuilds the translator
# and retranslates each src/foo.sml to src/foo.wm. Polls once a second (no inotify tools needed).
cd "$(dirname "$0")/.." || exit 1
last=""
while :; do
  now=$(stat -c '%y %n' src/*.sml src/subsetml.mlb lib/num.sml lib/subset_text_host.sml lib/subset_text_host.wm lib/subset_host.sml lib/subset_host.wm lib/subset_host.js Makefile 2>/dev/null | md5sum)
  if [ "$now" != "$last" ]; then
    last=$now
    if out=$(make -s bin/subsetml 2>&1) && out=$(make -s wm 2>&1); then
      echo "$(date +%T) src/*.wm updated"
    else
      echo "$(date +%T) FAILED:"
      echo "$out"
    fi
  fi
  sleep 1
done
