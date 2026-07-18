#!/usr/bin/env bash
# wait-save.sh <file> [max_seconds] — block until <file> is saved (mtime changes)
# and edits settle, then print a marker and exit. Used by the /plan loop: run this
# in the BACKGROUND so the user's `:w` in vim re-invokes the agent to process review.
set -uo pipefail

file="${1:?usage: wait-save.sh <file> [max_seconds]}"
max="${2:-1800}"     # give up after 30 min of no save
debounce=2           # seconds of quiet after a save before we call it settled

mtime() { stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null; }  # BSD/macOS || GNU/Linux

start="$(date +%s)"
last="$(mtime)"

while :; do
  sleep 1
  if [ $(( $(date +%s) - start )) -ge "$max" ]; then
    echo "TIMEOUT: no save within ${max}s — plan review still open."
    exit 2
  fi
  cur="$(mtime)"
  [ -z "$cur" ] && continue
  if [ "$cur" != "$last" ]; then
    # a save happened — debounce until edits settle
    while :; do
      sleep "$debounce"
      newer="$(mtime)"
      [ "$newer" = "$cur" ] && break
      cur="$newer"
    done
    echo "SAVED: $file"
    exit 0
  fi
done
