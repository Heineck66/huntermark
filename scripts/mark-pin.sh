#!/bin/bash
# HunterMark — pin / unpin marks.
#
# Pinned marks always occupy slots on the tmux status bar (subject to
# @huntermark-max-chips); remaining slots fill with the most recent
# unpinned marks. See scripts/mark-status.sh for the render rule.
#
# Usage:
#   mark-pin.sh mN[,mM,...]            set mN_pinned=1 for each
#   mark-pin.sh mN[,mM,...] --unset    remove mN_pinned for each
#
# Effects:
#   - Idempotent: re-pinning an already-pinned mark is a no-op.
#   - Logs `pin` / `unpin` entries to ~/.tmux/marks-history.log.
#   - Refreshes @huntermark-bar and the tmux status line.
set -e

F="$HOME/.tmux/marks.sh"
HISTORY="$HOME/.tmux/marks-history.log"
mkdir -p "$HOME/.tmux"

arg="${1:-}"
mode="set"
[ "${2:-}" = "--unset" ] && mode="unset"

if [ -z "$arg" ]; then
  echo "usage: $0 mN[,mM,...] [--unset]" >&2
  exit 1
fi
if [ ! -r "$F" ]; then
  echo "no marks file" >&2
  exit 1
fi

# Parse list of indices
indices=$(echo "$arg" | tr ',' '\n' | grep -oE 'm[0-9]+' | sort -u)
if [ -z "$indices" ]; then
  echo "usage: $0 mN[,mM,...] [--unset]" >&2
  exit 1
fi

ts=$(date -Iseconds)
changed=0
acted=""

for n in $indices; do
  if ! grep -qE "^export ${n}=" "$F"; then
    echo "$n not set; skipping" >&2
    continue
  fi

  if [ "$mode" = "set" ]; then
    if grep -qE "^export ${n}_pinned=" "$F"; then
      :  # already pinned; idempotent no-op
    else
      printf 'export %s_pinned=1\n' "$n" >> "$F"
      printf "%s\tpin\t%s\t-\n" "$ts" "$n" >> "$HISTORY"
      changed=1
      acted="${acted}${acted:+,}${n}"
    fi
  else
    if grep -qE "^export ${n}_pinned=" "$F"; then
      grep -vE "^export ${n}_pinned=" "$F" > "${F}.new"
      mv "${F}.new" "$F"
      printf "%s\tunpin\t%s\t-\n" "$ts" "$n" >> "$HISTORY"
      changed=1
      acted="${acted}${acted:+,}${n}"
    fi
  fi
done

if [ "$changed" -eq 1 ]; then
  "${0%/*}/mark-status.sh" >/dev/null 2>&1 || true
  tmux refresh-client -S 2>/dev/null || true
fi

if [ -t 1 ]; then
  if [ -n "$acted" ]; then
    echo "${mode}: ${acted}"
  else
    echo "${mode}: no change"
  fi
fi
