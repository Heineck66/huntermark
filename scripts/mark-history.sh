#!/bin/bash
# HunterMark — prints the history log.
# Usage:
#   mark-history.sh           tail last 20 entries
#   mark-history.sh 50        tail last 50
#   mark-history.sh all       full log
H="$HOME/.tmux/marks-history.log"
[ -r "$H" ] || { echo "no history" >&2; exit 1; }

arg="${1:-20}"

# Pretty-print: 4-column TSV (timestamp, action, mN, value) -> aligned columns
case "$arg" in
  all|--all|-a)
    cat "$H"
    ;;
  *[!0-9]*)
    echo "usage: $0 [N|all]" >&2; exit 1
    ;;
  *)
    tail -n "$arg" "$H"
    ;;
esac | column -t -s $'\t'
