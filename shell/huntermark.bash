# HunterMark — bash shell-side functions.
# Source from .bashrc:  source /path/to/huntermark/shell/huntermark.bash
#
# Same surface as huntermark.zsh (see that file for the full command list).

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
      local v n ip full ipvar
      for v in $(compgen -v 2>/dev/null); do
        [[ "$v" =~ ^m[0-9]+_full$ ]] || continue
        n="${v#m}"; n="${n%_full}"
        ipvar="m${n}"
        ip="${!ipvar}"
        full="${!v}"
        name=$(echo "$full" | sed "s|[[:space:]]*${ip}[[:space:]]*| |g; s/^[[:space:]]*//; s/[[:space:]]*$//")
        [ -z "$name" ] && name='-'
        printf 'm%s\t%s\t%s\n' "$n" "$name" "$ip"
      done | sort -k1.2 -n
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
    for v in $(compgen -v); do
      if [[ "$v" =~ ^m[0-9]+(_full)?$ ]]; then unset "$v"; fi
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
  if ! [[ "$n" =~ ^m[0-9]+$ ]]; then echo "expected mN (e.g. m1, m2)" >&2; return 1; fi
  [ -r "$HOME/.tmux/marks.sh" ] && source "$HOME/.tmux/marks.sh" 2>/dev/null
  local ip="${!n}"
  [ -z "$ip" ] && { echo "$n not set" >&2; return 1; }
  printf '%s' "$ip"
}

mssh() {
  # mssh mN [user] [ssh-flags...]
  # If the first arg after mN starts with `-`, it's an ssh flag and user
  # defaults to root. Otherwise it's the username and is shifted out; any
  # remaining args pass through to ssh.
  local n="$1"; shift || return 1
  local ip; ip=$(_mark_resolve "$n") || return 1
  local user="root"
  if [ "$#" -gt 0 ] && [ "${1:0:1}" != "-" ]; then user="$1"; shift; fi
  ssh "$@" "$user@$ip"
}
mnmap() { local n="$1"; shift; local ip; ip=$(_mark_resolve "$n") || return 1; nmap "$@" "$ip"; }
mcurl() { local n="$1"; shift; local ip; ip=$(_mark_resolve "$n") || return 1; curl "$@" "http://$ip"; }
mping() { local n="$1"; shift; local ip; ip=$(_mark_resolve "$n") || return 1; ping "$@" "$ip"; }

# PROMPT_COMMAND hook: source ~/.tmux/marks.sh before each prompt so $mN propagates across shells
_zero_load_marks() {
  [ -r "$HOME/.tmux/marks.sh" ] && source "$HOME/.tmux/marks.sh" 2>/dev/null
}
case ":$PROMPT_COMMAND:" in
  *":_zero_load_marks:"*) ;;
  *) PROMPT_COMMAND="_zero_load_marks${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
