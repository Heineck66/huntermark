#!/bin/bash
# HunterMark — edits an existing mark in place. Index stays stable.
# Usage:  mark-edit.sh m2 "Forge 10.10.10.43"
#   $1: target index (e.g. m2)
#   $2: new full input (will be re-parsed for IP)
set -e

F="$HOME/.tmux/marks.sh"
HISTORY="$HOME/.tmux/marks-history.log"
mkdir -p "$HOME/.tmux"

n="$1"
new_input="$2"

case "$n" in
  m[0-9]*) ;;
  *) echo "usage: $0 mN \"new value\"" >&2; exit 1 ;;
esac
[ -z "$new_input" ] && { echo "empty value; use unmark to remove" >&2; exit 1; }
[ -r "$F" ] || { echo "no marks file; use mark to create" >&2; exit 1; }

if ! grep -qE "^export ${n}=" "$F"; then
  echo "$n not set" >&2
  exit 1
fi

new_ip=$(echo "$new_input" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
[ -z "$new_ip" ] && new_ip="$new_input"

# Rewrite the file: replace the two lines for $n in-place, preserving everything else.
# Use bash builtins so %q-escaped values aren't re-interpreted (awk's -v eats backslashes).
{
  while IFS= read -r line; do
    case "$line" in
      "export ${n}="*)
        printf 'export %s=%q\n' "$n" "$new_ip"
        ;;
      "export ${n}_full="*)
        printf 'export %s_full=%q\n' "$n" "$new_input"
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done < "$F"
} > "${F}.new"
mv "${F}.new" "$F"

ts=$(date -Iseconds)
printf "%s\tedit\t%s\t%s\n" "$ts" "$n" "$new_input" >> "$HISTORY"

tmux refresh-client -S 2>/dev/null || true
if [ -t 1 ]; then echo "edited ${n}=${new_ip}"; fi
