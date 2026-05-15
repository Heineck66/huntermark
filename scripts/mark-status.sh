#!/bin/bash
# HunterMark — compute and publish the chip string for the tmux status bar.
#
# Effects:
#   1. Writes the rendered chip string to tmux user option @huntermark-bar.
#      Status-right should read it via #{@huntermark-bar} for instant updates
#      after every mark mutation (set/edit/remove/undo/pin/unpin) — this
#      bypasses tmux's status-interval cache on #() shell-format outputs.
#   2. Also prints the same string to stdout. This keeps the legacy
#      `#(.../mark-status.sh)` wiring working for installs that haven't
#      switched to the #{@huntermark-bar} pattern yet.
#
# If no marks remain, @huntermark-bar is unset (chip area clears).
#
# Render rule:
#   1. Partition marks into pinned (mN_pinned=1) and unpinned.
#   2. visible = sorted(pinned, by N asc)  ++  sorted(unpinned, by N desc).
#   3. Take the first MAX of visible  (MAX = @huntermark-max-chips, default 3).
#   4. Render those chips in ascending-N order for a stable display layout.
#   5. If any marks were dropped from the visible set, append "(+X)" overflow
#      chip in @huntermark-style-overflow (default fg=brightblack).
#
# Style/sizing user options:
#   @huntermark-style-index     (default: "fg=brightblack")
#   @huntermark-style-value     (default: "fg=yellow,bold")
#   @huntermark-style-pin       (default: "fg=cyan,bold")
#   @huntermark-style-overflow  (default: "fg=brightblack")
#   @huntermark-max-chips       (default: 3)

F="$HOME/.tmux/marks.sh"
out=""

# Scrub any inherited mN/mN_full/mN_host/mN_pinned from the parent environment
# before sourcing marks.sh. Otherwise, when this script runs as a child of the
# user's shell (via the mutation scripts), it would see stale exports left
# over from previously-removed marks and render them back into the chip —
# the exact bug that originally made `unmark m2` not clear the bar.
for _stale in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+(_full|_host|_pinned)?$'); do
  unset "$_stale"
done
unset _stale

if [ -r "$F" ]; then
  # shellcheck disable=SC1090
  . "$F" 2>/dev/null

  declare -A vals pinned
  for var in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+_full$'); do
    if [[ "$var" =~ ^m([0-9]+)_full$ ]]; then
      n="${BASH_REMATCH[1]}"
      vals["$n"]="${!var}"
      pin_var="m${n}_pinned"
      pinned["$n"]="${!pin_var:-}"
    fi
  done

  if [ ${#vals[@]} -gt 0 ]; then
    MAX=$(tmux show-option -gv @huntermark-max-chips 2>/dev/null)
    [ -z "$MAX" ] && MAX=3
    case "$MAX" in *[!0-9]*) MAX=3 ;; esac

    STYLE_IDX=$(tmux show-option -gv @huntermark-style-index 2>/dev/null)
    STYLE_VAL=$(tmux show-option -gv @huntermark-style-value 2>/dev/null)
    STYLE_PIN=$(tmux show-option -gv @huntermark-style-pin 2>/dev/null)
    STYLE_OVF=$(tmux show-option -gv @huntermark-style-overflow 2>/dev/null)
    [ -z "$STYLE_IDX" ] && STYLE_IDX="fg=brightblack"
    [ -z "$STYLE_VAL" ] && STYLE_VAL="fg=yellow,bold"
    [ -z "$STYLE_PIN" ] && STYLE_PIN="fg=cyan,bold"
    [ -z "$STYLE_OVF" ] && STYLE_OVF="fg=brightblack"

    # Partition by pin state.
    declare -a pinned_asc unpinned_desc
    mapfile -t pinned_asc   < <(for n in "${!vals[@]}"; do [ "${pinned[$n]}" = "1" ] && echo "$n"; done | sort -n)
    mapfile -t unpinned_desc < <(for n in "${!vals[@]}"; do [ "${pinned[$n]}" != "1" ] && echo "$n"; done | sort -nr)

    # Build visible set: pinned first (ascending), then unpinned (newest first),
    # capped at MAX. Then sort visible ascending for display.
    declare -a visible_raw=()
    for n in "${pinned_asc[@]}" "${unpinned_desc[@]}"; do
      [ "${#visible_raw[@]}" -ge "$MAX" ] && break
      visible_raw+=("$n")
    done
    mapfile -t visible < <(printf '%s\n' "${visible_raw[@]}" | sort -n)

    total=${#vals[@]}
    hidden=$((total - ${#visible[@]}))

    for n in "${visible[@]}"; do
      [ -n "$out" ] && out+=" | "
      if [ "${pinned[$n]}" = "1" ]; then
        # Pinned: tint the index chip differently to make pin state visible
        out+="#[${STYLE_PIN}]m${n}:#[${STYLE_VAL}] ${vals[$n]}"
      else
        out+="#[${STYLE_IDX}]m${n}:#[${STYLE_VAL}] ${vals[$n]}"
      fi
    done

    if [ "$hidden" -gt 0 ]; then
      [ -n "$out" ] && out+=" | "
      out+="#[${STYLE_OVF}](+${hidden})"
    fi

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
