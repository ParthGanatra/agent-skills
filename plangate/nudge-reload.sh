#!/usr/bin/env bash
# nudge-reload.sh — tell the tracked plan vim pane to reload the file from disk
# after the agent has resolved the review markers. Uses :checktime, which with autoread
# reloads only when the buffer has no unsaved changes (won't clobber live edits).
set -uo pipefail

[ -z "${TMUX:-}" ] && exit 0
pane="$(tmux show-option -gqv @plangate_pane 2>/dev/null || true)"
[ -z "$pane" ] && exit 0

# confirm the tracked pane still exists and is running vim
cmd="$(tmux list-panes -a -F '#{pane_id} #{pane_current_command}' \
      | awk -v p="$pane" '$1==p{print tolower($2)}')"
printf '%s\n' "$cmd" | grep -qE '^(vim|nvim|view|vi)$' || exit 0

tmux send-keys -t "$pane" Escape
sleep 0.15   # same ESC-debounce as open-plan.sh, so ':' isn't read as <M-:>
tmux send-keys -t "$pane" ':checktime' Enter
echo "Nudged pane $pane to reload."
