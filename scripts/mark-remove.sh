#!/bin/bash
# HunterMark — removes marks. Argument forms:
#   all          -> wipe entire marks.sh; trash gets every entry
#   m1           -> remove mark 1; soft-deleted to trash
#   m1,m3        -> remove multiple (gaps preserved; numbering does not renumber)
#
# Soft delete: removed entries are appended to ~/.tmux/marks-trash.sh with a
# `# deleted <ts>` header. Trash is capped at HUNTERMARK_TRASH_LIMIT (default 20)
# most recent deletion blocks. `mark undo` pops the most recent block back.
#
# Input source (in order):
#   1. Command-line arg ($1) — used by `unmark` shell function
#   2. Tmux user option @mark-remove — used by the `prefix + alt + t` binding
set -e

F="$HOME/.tmux/marks.sh"
TRASH="$HOME/.tmux/marks-trash.sh"
HISTORY="$HOME/.tmux/marks-history.log"
LIMIT="${HUNTERMARK_TRASH_LIMIT:-20}"
mkdir -p "$HOME/.tmux"

arg="${1:-}"
if [ -z "$arg" ]; then
  arg=$(tmux show-option -gv @mark-remove 2>/dev/null || true)
fi
tmux set-option -gu @mark-remove >/dev/null 2>&1 || true

[ -z "$arg" ] && exit 0
[ -r "$F" ] || { tmux refresh-client -S 2>/dev/null || true; exit 0; }

ts=$(date -Iseconds)

# Helper: capture matching entries to trash + history, then strip from main file
_capture_and_strip() {
  local pattern="$1"
  local removed_indices
  removed_indices=$(grep -oE "^export m[0-9]+=" "$F" 2>/dev/null \
                    | sed 's/export //; s/=//' | sort -un \
                    | grep -E "$pattern" || true)
  [ -z "$removed_indices" ] && return 0

  for n in $removed_indices; do
    {
      printf "# deleted %s\n" "$ts"
      grep -E "^export ${n}(=|_full=)" "$F"
    } >> "$TRASH"

    # Resolve the unescaped value by sourcing the entry in a subshell
    local full
    full=$(grep -E "^export ${n}_full=" "$F" 2>/dev/null \
           | (source /dev/stdin 2>/dev/null; ref="${n}_full"; printf '%s' "${!ref}"))
    printf "%s\tremove\t%s\t%s\n" "$ts" "$n" "$full" >> "$HISTORY"
  done

  local strip_re="^export (${pattern//[\^\$]/})(=|_full=)"
  grep -vE "$strip_re" "$F" > "${F}.new" || true
  mv "${F}.new" "$F"
}

if [ "$arg" = "all" ]; then
  _capture_and_strip "m[0-9]+"
  rm -f "$F"
  if [ -t 1 ]; then echo "removed: all"; fi
else
  spec=$(echo "$arg" | tr ',' '\n' | grep -oE 'm[0-9]+' | sed 's/^m//' | tr '\n' '|' | sed 's/|$//')
  if [ -z "$spec" ]; then
    echo "usage: $0 all | mN | mN,mM" >&2
    exit 1
  fi
  pattern="m(${spec})"
  _capture_and_strip "$pattern"
  [ ! -s "$F" ] && rm -f "$F"
  if [ -t 1 ]; then echo "removed: $arg"; fi
fi

# Trim trash to last LIMIT deletion blocks
if [ -r "$TRASH" ]; then
  total=$(grep -c '^# deleted ' "$TRASH" 2>/dev/null || echo 0)
  if [ "$total" -gt "$LIMIT" ]; then
    skip=$((total - LIMIT))
    awk -v skip="$skip" '
      /^# deleted / { count++ }
      count > skip
    ' "$TRASH" > "${TRASH}.new"
    mv "${TRASH}.new" "$TRASH"
  fi
fi

tmux refresh-client -S 2>/dev/null || true
