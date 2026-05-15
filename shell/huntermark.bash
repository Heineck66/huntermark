# HunterMark — bash shell-side functions.
# Source from .bashrc:  source /path/to/huntermark/shell/huntermark.bash
#
# Same surface as huntermark.zsh (see that file for the full command list).

: "${HUNTERMARK_HELPER_DIR:=$HOME/.config/tmux}"
: "${HUNTERMARK_HELP_FILE:=$HOME/.config/tmux/huntermark-help.txt}"

# Convert args (m1 m2 / 1 2 / m1,m2) -> canonical mN,mN csv. Internal helper.
_mark_args_to_csv() {
  local out="" tok arg
  for arg in "$@"; do
    IFS=',' read -ra _toks <<< "$arg"
    for tok in "${_toks[@]}"; do
      tok="${tok#m}"
      [[ "$tok" =~ ^[0-9]+$ ]] && out="${out}${out:+,}m${tok}"
    done
  done
  printf '%s' "$out"
}

mark() {
  if [ "$#" -eq 0 ]; then
    if [ ! -r "$HOME/.tmux/marks.sh" ]; then
      echo "no marks set" >&2; return 1
    fi
    source "$HOME/.tmux/marks.sh"

    local has_host=0 v
    for v in $(compgen -v 2>/dev/null); do
      [[ "$v" =~ ^m[0-9]+_host$ ]] && { has_host=1; break; }
    done

    {
      if [ "$has_host" -eq 1 ]; then
        printf 'INDEX\tNAME\tIP\tHOST\tPIN\n'
      else
        printf 'INDEX\tNAME\tIP\tPIN\n'
      fi
      local n ip host pinned full ipvar hostvar pinvar pin_mark name
      for v in $(compgen -v 2>/dev/null); do
        [[ "$v" =~ ^m[0-9]+_full$ ]] || continue
        n="${v#m}"; n="${n%_full}"
        ipvar="m${n}";    ip="${!ipvar}"
        hostvar="m${n}_host"; host="${!hostvar:-}"
        pinvar="m${n}_pinned"; pinned="${!pinvar:-}"
        full="${!v}"
        name="$full"
        [ -n "$ip" ]   && name=$(echo "$name" | sed "s|[[:space:]]*${ip}[[:space:]]*| |g")
        [ -n "$host" ] && name=$(echo "$name" | sed "s|[[:space:]]*${host}[[:space:]]*| |gI")
        name=$(echo "$name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -z "$name" ] && name='-'
        pin_mark='-'
        [ "$pinned" = "1" ] && pin_mark='*'
        if [ "$has_host" -eq 1 ]; then
          [ -z "$host" ] && host='-'
          printf 'm%s\t%s\t%s\t%s\t%s\n' "$n" "$name" "$ip" "$host" "$pin_mark"
        else
          printf 'm%s\t%s\t%s\t%s\n' "$n" "$name" "$ip" "$pin_mark"
        fi
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
    pin)
      shift
      local csv
      csv=$(_mark_args_to_csv "$@")
      if [ -z "$csv" ]; then
        if [ ! -r "$HOME/.tmux/marks.sh" ]; then
          echo "no marks set" >&2; return 1
        fi
        source "$HOME/.tmux/marks.sh"
        local var pn pinned_list=""
        for var in $(compgen -v 2>/dev/null); do
          [[ "$var" =~ ^m[0-9]+_pinned$ ]] || continue
          [ "${!var}" = "1" ] || continue
          pn="${var%_pinned}"
          pinned_list="${pinned_list}${pinned_list:+, }${pn}"
        done
        if [ -n "$pinned_list" ]; then
          echo "pinned: ${pinned_list}"
        else
          echo "no pinned marks"
        fi
        return 0
      fi
      "$HUNTERMARK_HELPER_DIR/mark-pin.sh" "$csv"
      source "$HOME/.tmux/marks.sh" 2>/dev/null
      return 0
      ;;
    unpin)
      shift
      local csv
      csv=$(_mark_args_to_csv "$@")
      if [ -z "$csv" ]; then
        echo "usage: mark unpin mN [mM ...]" >&2
        return 1
      fi
      "$HUNTERMARK_HELPER_DIR/mark-pin.sh" "$csv" --unset
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
      if [[ "$v" =~ ^m[0-9]+(_full|_host|_pinned)?$ ]]; then unset "$v"; fi
    done
  else
    local n
    for n in $(echo "$arg" | tr ',' ' ' | grep -oE 'm[0-9]+'); do
      unset "$n" "${n}_full" "${n}_host" "${n}_pinned"
    done
  fi
}

# Resolve mN -> primary value ($mN). Echo it, return 1 if not set.
_mark_resolve() {
  local n="$1"
  if ! [[ "$n" =~ ^m[0-9]+$ ]]; then echo "expected mN (e.g. m1, m2)" >&2; return 1; fi
  [ -r "$HOME/.tmux/marks.sh" ] && source "$HOME/.tmux/marks.sh" 2>/dev/null
  local val="${!n}"
  [ -z "$val" ] && { echo "$n not set" >&2; return 1; }
  printf '%s' "$val"
}

# Resolve mN -> hostname. Prefers $mN_host, falls back to $mN. Fails if the
# resolved value contains no letters (it's an IPv4) — Kerberos-aware tools
# would just complain about the bare IP, so we fail loudly here.
mhost() {
  local n="$1"
  if ! [[ "$n" =~ ^m[0-9]+$ ]]; then echo "expected mN (e.g. m1, m2)" >&2; return 1; fi
  [ -r "$HOME/.tmux/marks.sh" ] && source "$HOME/.tmux/marks.sh" 2>/dev/null
  local host_var="${n}_host"
  local host="${!host_var:-${!n}}"
  [ -z "$host" ] && { echo "$n not set" >&2; return 1; }
  [[ "$host" =~ [A-Za-z] ]] || { echo "$n has no hostname (only IPv4): $host" >&2; return 1; }
  printf '%s' "$host"
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
