#!/bin/bash
# HunterMark — restores the most recent deletion from trash.
# If the original index is free, restored at the same index.
# If the original index is now occupied, restored at the next free index.
set -e

F="$HOME/.tmux/marks.sh"
TRASH="$HOME/.tmux/marks-trash.sh"
HISTORY="$HOME/.tmux/marks-history.log"
mkdir -p "$HOME/.tmux"

[ -r "$TRASH" ] || { echo "trash empty" >&2; exit 1; }

# Find the line number of the LAST `# deleted` block in the trash
last_marker_line=$(grep -n '^# deleted ' "$TRASH" | tail -1 | cut -d: -f1)
[ -z "$last_marker_line" ] && { echo "trash empty" >&2; exit 1; }

# Extract the block (header + the export lines that follow it, up to the next # or EOF)
block=$(awk -v start="$last_marker_line" '
  NR == start { in_block=1; print; next }
  in_block && /^# deleted / { exit }
  in_block { print }
' "$TRASH")

# The export lines from the block (skip the `# deleted` header)
exports=$(echo "$block" | grep '^export m')
[ -z "$exports" ] && { echo "trash entry has no export lines; aborting" >&2; exit 1; }

# Original index from the first export line
orig_n=$(echo "$exports" | head -1 | grep -oE 'export m[0-9]+' | sed 's/export m//')

# Decide target index
target_n="$orig_n"
if [ -r "$F" ] && grep -qE "^export m${orig_n}=" "$F"; then
  # Conflict — pick next free
  max=$(grep -oE '^export m[0-9]+=' "$F" 2>/dev/null \
        | sed 's/export m//; s/=//' | sort -n | tail -1)
  target_n=$((max + 1))
  echo "  m${orig_n} taken; restoring as m${target_n}" >&2
fi

# Re-emit the export lines with target_n substituted
restored=$(echo "$exports" \
  | sed "s|^export m${orig_n}=|export m${target_n}=|" \
  | sed "s|^export m${orig_n}_full=|export m${target_n}_full=|")

echo "$restored" >> "$F"

# Remove the popped block from trash
head -n $((last_marker_line - 1)) "$TRASH" > "${TRASH}.new"
mv "${TRASH}.new" "$TRASH"
[ ! -s "$TRASH" ] && rm -f "$TRASH"

# Log to history (resolve unescaped value via subshell source)
ts=$(date -Iseconds)
full=$(echo "$restored" | grep "_full=" \
       | (source /dev/stdin 2>/dev/null; ref="m${target_n}_full"; printf '%s' "${!ref}"))
printf "%s\tundo\tm%s\t%s\n" "$ts" "$target_n" "$full" >> "$HISTORY"

"${0%/*}/mark-status.sh" >/dev/null 2>&1 || true
tmux refresh-client -S 2>/dev/null || true
if [ -t 1 ]; then echo "restored m${target_n}"; fi
