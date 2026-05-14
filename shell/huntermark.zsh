# HunterMark — zsh shell-side functions.
# Source from .zshrc:  source /path/to/huntermark/shell/huntermark.zsh
#
# Provides:
#   mark / unmark              add and remove marks
#   mark edit mN <val>         edit existing mark in place (index stable)
#   mark undo                  restore most recent deletion
#   mark history [N|all]       print operation log
#   mark help                  open the cheatsheet popup
#   mssh / mnmap / mcurl / mping  quick wrappers around $mN
#   _mark_resolve              resolve mN -> IP (internal)
#   _zero_load_marks           precmd hook (auto-installed)
#
# Helper scripts are expected at ${HUNTERMARK_HELPER_DIR:-$HOME/.config/tmux}.
# When installed via TPM, install.sh sets HUNTERMARK_HELPER_DIR to the plugin's scripts/ dir.

: "${HUNTERMARK_HELPER_DIR:=$HOME/.config/tmux}"
: "${HUNTERMARK_HELP_FILE:=$HOME/.config/tmux/huntermark-help.txt}"

mark() {
  if [ "$#" -eq 0 ]; then
    if [ ! -r "$HOME/.tmux/marks.sh" ]; then
      echo "no marks set" >&2
      return 1
    fi
    source "$HOME/.tmux/marks.sh"
    {
      printf 'INDEX\tNAME\tIP\n'
      local n name ip full var_full var_ip
      for var_full in ${(ko)parameters}; do
        case "$var_full" in m<->_full) ;; *) continue ;; esac
        n="${var_full#m}"; n="${n%_full}"
        var_ip="m${n}"
        ip="${(P)var_ip}"
        full="${(P)var_full}"
        name=$(echo "$full" | sed "s|[[:space:]]*${ip}[[:space:]]*| |g; s/^[[:space:]]*//; s/[[:space:]]*$//")
        [ -z "$name" ] && name='-'
        printf 'm%s\t%s\t%s\n' "$n" "$name" "$ip"
      done | sort -t m -k2 -n
    } | column -t -s $'\t'
    return 0
  fi
  case "$1" in
    help)
      if command -v tmux >/dev/null && [ -n "$TMUX" ]; then
        tmux display-popup -E -w 90% -h 90% "less -N -i -S '$HUNTERMARK_HELP_FILE'"
      else
        less -N -i -S "$HUNTERMARK_HELP_FILE"
      fi
      return 0
      ;;
    edit)
      shift
      local n="$1"; shift
      "$HUNTERMARK_HELPER_DIR/mark-edit.sh" "$n" "$*"
      source "$HOME/.tmux/marks.sh" 2>/dev/null
      return 0
      ;;
    undo)
      "$HUNTERMARK_HELPER_DIR/mark-undo.sh"
      source "$HOME/.tmux/marks.sh" 2>/dev/null
      return 0
      ;;
    history)
      shift
      "$HUNTERMARK_HELPER_DIR/mark-history.sh" "$@"
      return 0
      ;;
  esac
  "$HUNTERMARK_HELPER_DIR/mark-set.sh" "$*"
  source "$HOME/.tmux/marks.sh" 2>/dev/null
}

unmark() {
  local arg="${1:-all}"
  local force="${2:-}"
  if [ "$arg" = "all" ] && [ "$force" != "-y" ]; then
    local count=0
    [ -r "$HOME/.tmux/marks.sh" ] && \
      count=$(grep -c '^export m[0-9]\+=' "$HOME/.tmux/marks.sh" 2>/dev/null || echo 0)
    if [ "$count" -gt 0 ]; then
      printf 'really clear all %d mark(s)? [y/N] ' "$count"
      local reply
      read -r reply
      case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "cancelled"; return 0 ;;
      esac
    fi
  fi
  "$HUNTERMARK_HELPER_DIR/mark-remove.sh" "$arg"
  if [ "$arg" = "all" ]; then
    local v
    for v in ${(k)parameters}; do
      case "$v" in m<->|m<->_full) unset "$v" ;; esac
    done
  else
    local n
    for n in $(echo "$arg" | tr ',' ' ' | grep -oE 'm[0-9]+'); do
      unset "$n" "${n}_full"
    done
  fi
}

# Resolve mN -> IP. Echo the IP, return 1 if not set.
_mark_resolve() {
  local n="$1"
  case "$n" in m<->) ;; *) echo "expected mN (e.g. m1, m2)" >&2; return 1 ;; esac
  [ -r "$HOME/.tmux/marks.sh" ] && source "$HOME/.tmux/marks.sh" 2>/dev/null
  local ip="${(P)n}"
  [ -z "$ip" ] && { echo "$n not set" >&2; return 1; }
  printf '%s' "$ip"
}

mssh()  { local n="$1"; local u="${2:-root}"; local ip; ip=$(_mark_resolve "$n") || return 1; ssh "$u@$ip"; }
mnmap() { local n="$1"; shift; local ip; ip=$(_mark_resolve "$n") || return 1; nmap "$@" "$ip"; }
mcurl() { local n="$1"; shift; local ip; ip=$(_mark_resolve "$n") || return 1; curl "$@" "http://$ip"; }
mping() { local n="$1"; shift; local ip; ip=$(_mark_resolve "$n") || return 1; ping "$@" "$ip"; }

# precmd hook: source ~/.tmux/marks.sh on every prompt so $mN propagates across panes
_zero_load_marks() {
  [ -r "$HOME/.tmux/marks.sh" ] && source "$HOME/.tmux/marks.sh" 2>/dev/null
}
typeset -ga precmd_functions
[[ "${precmd_functions[(r)_zero_load_marks]}" != "_zero_load_marks" ]] && precmd_functions+=(_zero_load_marks)
