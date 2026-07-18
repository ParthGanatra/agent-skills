#!/usr/bin/env bash
# Delete plan files not touched in N days. Run at the start of every /plan.
# A plan being actively reviewed gets its mtime bumped on every :w, so only
# finished or abandoned plans age out.
#
# Usage: prune-plans.sh <plans-dir> [days]
#        days: arg > $PLAN_RETENTION_DAYS > 7

set -uo pipefail

dir="${1:-}"
days="${2:-${PLAN_RETENTION_DAYS:-7}}"

[ -n "$dir" ] || { echo "usage: prune-plans.sh <plans-dir> [days]" >&2; exit 2; }
[ -d "$dir" ] || exit 0

pruned=0
while IFS= read -r f; do
    rm -f "$f" && echo "pruned: $f" && pruned=$((pruned + 1))
done < <(find "$dir" -maxdepth 1 -type f -name '*.md' -mtime "+${days}" 2>/dev/null)

[ "$pruned" -eq 0 ] && echo "pruned: none (nothing older than ${days}d in $dir)"
exit 0
