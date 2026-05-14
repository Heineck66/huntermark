#!/bin/bash
# HunterMark — compute and publish the chip string for the tmux status bar.
#
# Effects:
#   1. Writes the rendered chip string to tmux user option @huntermark-bar.
#      Status-right should read it via #{@huntermark-bar} for instant updates
#      after every mark mutation (set/edit/remove/undo) — this bypasses tmux's
#      status-interval cache on #() shell-format outputs.
#   2. Also prints the same string to stdout. This keeps the legacy
#      `#(.../mark-status.sh)` wiring working for installs that haven't
#      switched to the #{@huntermark-bar} pattern yet.
#
# If no marks remain, @huntermark-bar is unset (chip area clears).
#
# Style/sizing user options:
#   @huntermark-style-index   (default: "fg=brightblack")
#   @huntermark-style-value   (default: "fg=yellow,bold")
#   @huntermark-max-chips     (default: 3)

F="$HOME/.tmux/marks.sh"
out=""

# Scrub any inherited mN/mN_full from the parent environment first. Otherwise,
# when this script runs as a child of the user's shell (via the mutation
# scripts), it would see stale exports left over from previously-removed
# marks and render them back into the chip — the exact bug that made
# `unmark m2` look like it wasn't clearing the bar.
for _stale in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+(_full)?$'); do
  unset "$_stale"
done
unset _stale

if [ -r "$F" ]; then
  . "$F" 2>/dev/null

  declare -A vals
  for var in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+_full$'); do
    if [[ "$var" =~ ^m([0-9]+)_full$ ]]; then
      n="${BASH_REMATCH[1]}"
      vals["$n"]="${!var}"
    fi
  done

  if [ ${#vals[@]} -gt 0 ]; then
    MAX=$(tmux show-option -gv @huntermark-max-chips 2>/dev/null)
    [ -z "$MAX" ] && MAX=3
    case "$MAX" in *[!0-9]*) MAX=3 ;; esac

    STYLE_IDX=$(tmux show-option -gv @huntermark-style-index 2>/dev/null)
    STYLE_VAL=$(tmux show-option -gv @huntermark-style-value 2>/dev/null)
    [ -z "$STYLE_IDX" ] && STYLE_IDX="fg=brightblack"
    [ -z "$STYLE_VAL" ] && STYLE_VAL="fg=yellow,bold"

    mapfile -t nums < <(printf '%s\n' "${!vals[@]}" | sort -n)
    total=${#nums[@]}
    start=0
    [ "$total" -gt "$MAX" ] && start=$((total - MAX))

    for ((i=start; i<total; i++)); do
      n="${nums[$i]}"
      [ -n "$out" ] && out+=" | "
      out+="#[${STYLE_IDX}]m${n}:#[${STYLE_VAL}] ${vals[$n]}"
    done

    [ -n "$out" ] && out="${out} | "
  fi
fi

if command -v tmux >/dev/null 2>&1; then
  if [ -n "$out" ]; then
    tmux set-option -gq @huntermark-bar "$out" 2>/dev/null || true
  else
    tmux set-option -gu @huntermark-bar 2>/dev/null || true
  fi
fi

[ -n "$out" ] && printf '%s' "$out"
