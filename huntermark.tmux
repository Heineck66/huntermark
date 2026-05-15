#!/usr/bin/env bash
# HunterMark — TPM entrypoint.
# Registers tmux bindings. Status-bar widget is opt-in: see README to wire it
# into your status-right. Shell-side functions install separately via install.sh.

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Configurable chord prefixes via tmux user options (defaults match the documented set)
CHORD_ADD=$(tmux show-option -gv @huntermark-chord-add 2>/dev/null)
CHORD_REMOVE=$(tmux show-option -gv @huntermark-chord-remove 2>/dev/null)
CHORD_HELP=$(tmux show-option -gv @huntermark-chord-help 2>/dev/null)
CHORD_POPUP=$(tmux show-option -gv @huntermark-chord-popup 2>/dev/null)
[ -z "$CHORD_ADD" ]    && CHORD_ADD='t'
[ -z "$CHORD_REMOVE" ] && CHORD_REMOVE='M-t'
[ -z "$CHORD_HELP" ]   && CHORD_HELP='M-h'
[ -z "$CHORD_POPUP" ]  && CHORD_POPUP='m'

# Add a mark — opens command-prompt, pipes input through @mark-input -> mark-set.sh
tmux bind-key "$CHORD_ADD" command-prompt -p 'mark target:' \
  "set -g @mark-input '%%' ; run-shell -b '$CURRENT_DIR/scripts/mark-set.sh'"

# Remove marks — opens command-prompt, pipes through @mark-remove -> mark-remove.sh
tmux bind-key "$CHORD_REMOVE" command-prompt -p 'remove marks (all|mN|csv):' \
  "set -g @mark-remove '%%' ; run-shell -b '$CURRENT_DIR/scripts/mark-remove.sh'"

# Open the cheatsheet in a popup
tmux bind-key "$CHORD_HELP" display-popup -E -w 90% -h 90% \
  "less -N -i -S '$CURRENT_DIR/docs/help.txt'"

# Open the all-marks interactive popup (browse, pin, unpin)
tmux bind-key "$CHORD_POPUP" display-popup -E -w 80% -h 80% \
  "'$CURRENT_DIR/scripts/mark-popup.sh'"

# Expose the status-widget path as a tmux user option so users can reference it
# in their status-right with the legacy: #(#{@huntermark-widget-path})
tmux set-option -g @huntermark-widget-path "$CURRENT_DIR/scripts/mark-status.sh"

# Seed @huntermark-bar from any existing marks.sh so the recommended
# `set -g status-right "#{@huntermark-bar} ..."` wiring renders immediately
# on tmux start, before the user has touched any mark this session.
"$CURRENT_DIR/scripts/mark-status.sh" >/dev/null 2>&1 || true
