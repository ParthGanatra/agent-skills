#!/usr/bin/env bash
# open-plan.sh — open or focus a plan file in a right-side tmux vim pane.
# Used by the /plan skill. Safe no-op outside tmux (prints the path).
#
# Behavior (locked in the plan-skill design):
#   1. If this same file was already opened by us and that vim pane is alive -> focus it.
#   2. Else if a vim pane exists to the RIGHT of the active pane -> :e the file there.
#   3. Else split a new right pane and open vim on the file.
#   4. Not in tmux -> just print the path.
set -uo pipefail

file="${1:?usage: open-plan.sh <plan-file>}"
# absolutize the path
file="$(cd "$(dirname "$file")" 2>/dev/null && pwd)/$(basename "$file")"

if [ -z "${TMUX:-}" ]; then
  echo "Not in tmux — open it yourself:  vim '$file'"
  exit 0
fi

vim_re='^(vim|nvim|view|vi)$'

# --- 1. tracked pane from a previous open of this same file ---
tracked_pane="$(tmux show-option -gqv @plangate_pane 2>/dev/null || true)"
tracked_file="$(tmux show-option -gqv @plangate_file 2>/dev/null || true)"
if [ -n "$tracked_pane" ] && [ "$tracked_file" = "$file" ]; then
  cmd="$(tmux list-panes -a -F '#{pane_id} #{pane_current_command}' \
        | awk -v p="$tracked_pane" '$1==p{print tolower($2)}')"
  if printf '%s\n' "$cmd" | grep -qE "$vim_re"; then
    tmux select-pane -t "$tracked_pane"
    echo "Focused existing plan pane $tracked_pane."
    exit 0
  fi
fi

# We deliberately DO NOT hijack an arbitrary right-side vim pane — that would yank
# you away from a file you're working on. The plan always gets its own pane: reuse
# only our tracked pane (above), otherwise split a fresh one (below).

# --- 2. split a new right pane and open vim ---
new_pane="$(tmux split-window -h -P -F '#{pane_id}' -c "$(dirname "$file")" "vim -c 'set autoread' '$file'")"
tmux set-option -g @plangate_pane "$new_pane"
tmux set-option -g @plangate_file "$file"
echo "Split a new right pane ($new_pane) and opened vim."
