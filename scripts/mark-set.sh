#!/bin/bash
# HunterMark — adds a mark.
# Input source (in order):
#   1. Command-line arg ($1) — used by the `mark` shell function
#   2. Tmux user option @mark-input — used by the `prefix + t` binding
#
# Effect:
#   - Appends `export mN=<ip>` and `export mN_full=<input>` to ~/.tmux/marks.sh
#   - N auto-increments based on existing entries (gaps preserved on removal)
#   - First IPv4 in input becomes $mN; on miss, first hostname-shaped token
#     (alnum/dash + dot, e.g. forge.htb) is accepted; otherwise the call is
#     rejected so `mark --help` / `mark foo` can't pollute the file.
#   - Logs the add operation to ~/.tmux/marks-history.log
set -e

MARKS_FILE="$HOME/.tmux/marks.sh"
HISTORY_FILE="$HOME/.tmux/marks-history.log"
mkdir -p "$HOME/.tmux"

input="$1"
if [ -z "$input" ]; then
  input=$(tmux show-option -gv @mark-input 2>/dev/null || true)
fi
tmux set-option -gu @mark-input >/dev/null 2>&1 || true

[ -z "$input" ] && exit 0

next=1
if [ -r "$MARKS_FILE" ]; then
  max=$(grep -oE '^export m[0-9]+=' "$MARKS_FILE" 2>/dev/null \
        | sed 's/export m//; s/=//' \
        | sort -n | tail -1)
  [ -n "$max" ] && next=$((max + 1))
fi

ip=$(echo "$input" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
if [ -z "$ip" ]; then
  ip=$(echo "$input" | grep -oE '[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+' | head -1)
fi
if [ -z "$ip" ]; then
  msg="mark: missing ip/hostname (got: ${input})"
  echo "$msg" >&2
  echo "usage: mark <name> <ip-or-hostname>" >&2
  tmux display-message "$msg" 2>/dev/null || true
  exit 1
fi

{
  printf "export m%d=%q\n"      "$next" "$ip"
  printf "export m%d_full=%q\n" "$next" "$input"
} >> "$MARKS_FILE"

ts=$(date -Iseconds)
printf "%s\tadd\tm%d\t%s\n" "$ts" "$next" "$input" >> "$HISTORY_FILE"

"${0%/*}/mark-status.sh" >/dev/null 2>&1 || true
tmux refresh-client -S 2>/dev/null || true
if [ -t 1 ]; then echo "marked m${next}=${ip}"; fi
