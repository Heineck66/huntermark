#!/bin/bash
# HunterMark — tmux status-bar widget. Reads ~/.tmux/marks.sh, takes the most
# recent 3 mN_full entries (by N), joins with " | ", emits per-chip:
#   "m<N>: <value>"  (mN dimmed in brightblack, value in yellow bold)
#
# Style is configurable via tmux user options:
#   @huntermark-style-index    (default: "fg=brightblack")
#   @huntermark-style-value    (default: "fg=yellow,bold")
#   @huntermark-max-chips      (default: 3)
F="$HOME/.tmux/marks.sh"
[ -r "$F" ] || exit 0

. "$F" 2>/dev/null

declare -A vals
for var in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+_full$'); do
  if [[ "$var" =~ ^m([0-9]+)_full$ ]]; then
    n="${BASH_REMATCH[1]}"
    vals["$n"]="${!var}"
  fi
done

[ ${#vals[@]} -eq 0 ] && exit 0

# Configurable max-chips
MAX=$(tmux show-option -gv @huntermark-max-chips 2>/dev/null)
[ -z "$MAX" ] && MAX=3
case "$MAX" in *[!0-9]*) MAX=3 ;; esac

# Configurable styles
STYLE_IDX=$(tmux show-option -gv @huntermark-style-index 2>/dev/null)
STYLE_VAL=$(tmux show-option -gv @huntermark-style-value 2>/dev/null)
[ -z "$STYLE_IDX" ] && STYLE_IDX="fg=brightblack"
[ -z "$STYLE_VAL" ] && STYLE_VAL="fg=yellow,bold"

mapfile -t nums < <(printf '%s\n' "${!vals[@]}" | sort -n)
total=${#nums[@]}
start=0
[ "$total" -gt "$MAX" ] && start=$((total - MAX))

out=""
for ((i=start; i<total; i++)); do
  n="${nums[$i]}"
  [ -n "$out" ] && out+=" | "
  out+="#[${STYLE_IDX}]m${n}:#[${STYLE_VAL}] ${vals[$n]}"
done

printf '%s | ' "$out"
