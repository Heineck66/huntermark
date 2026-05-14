#!/usr/bin/env bash
# HunterMark — shell-side installer.
#
# When HunterMark is installed via TPM, you still need to wire the shell-side
# functions (mark / unmark / mssh / ...) into your shell rc. This script
# detects your shell, appends a single source line to the rc, and copies the
# cheatsheet to ~/.config/tmux/ for the popup binding.
#
# Idempotent: re-running is safe; nothing is duplicated.
set -e

PLUGIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TARGET_DIR="$HOME/.config/tmux"
HELP_SRC="$PLUGIN_DIR/docs/help.txt"
HELP_DST="$TARGET_DIR/huntermark-help.txt"

mkdir -p "$TARGET_DIR" "$HOME/.tmux"

# Copy the cheatsheet so the prefix+M-h popup works regardless of plugin path
if [ -r "$HELP_SRC" ]; then
  cp "$HELP_SRC" "$HELP_DST"
  echo "  installed cheatsheet -> $HELP_DST"
fi

detect_rc() {
  case "$(basename "$SHELL")" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) echo "$HOME/.bashrc" ;;
    *)    echo "" ;;
  esac
}

write_rc() {
  local rc="$1" snippet="$2" tag="$3"
  if grep -qF "$tag" "$rc" 2>/dev/null; then
    echo "  shell snippet already present in $rc"
    return 0
  fi
  printf '\n# === HunterMark === %s\n%s\n' "$tag" "$snippet" >> "$rc"
  echo "  appended snippet to $rc"
}

main() {
  local shell="${1:-$(basename "$SHELL")}"
  local rc snippet
  case "$shell" in
    zsh)
      rc="$HOME/.zshrc"
      snippet="export HUNTERMARK_HELPER_DIR='$PLUGIN_DIR/scripts'
export HUNTERMARK_HELP_FILE='$HELP_DST'
source '$PLUGIN_DIR/shell/huntermark.zsh'"
      ;;
    bash)
      rc="$HOME/.bashrc"
      snippet="export HUNTERMARK_HELPER_DIR='$PLUGIN_DIR/scripts'
export HUNTERMARK_HELP_FILE='$HELP_DST'
source '$PLUGIN_DIR/shell/huntermark.bash'"
      ;;
    *)
      echo "Unsupported shell: $shell. Edit your rc manually:" >&2
      echo "  source $PLUGIN_DIR/shell/huntermark.{zsh,bash}" >&2
      exit 2
      ;;
  esac
  write_rc "$rc" "$snippet" "huntermark-$shell"
  echo
  echo "Done. Open a new shell or run:  source $rc"
  echo "Then test with:  mark help"
}

main "$@"
