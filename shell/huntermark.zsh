# HunterMark — zsh shell-side functions.
# Source from .zshrc:  source /path/to/huntermark/shell/huntermark.zsh
#
# Provides:
#   mark / unmark                  add and remove marks
#   mark edit mN <val>             edit existing mark in place (index stable)
#   mark pin mN[,mM,...]           pin marks to the status bar
#   mark unpin mN[,mM,...]         unpin marks
#   mark undo                      restore most recent deletion
#   mark history [N|all]           print operation log
#   mark help                      open the cheatsheet popup
#   mssh / mnmap / mcurl / mping   quick wrappers around $mN
#   mhost mN                       resolve mN -> hostname (for Kerberos tools)
#   _mark_resolve                  resolve mN -> primary value (internal)
#   _zero_load_marks               precmd hook (auto-installed)
#
# Helper scripts are expected at ${HUNTERMARK_HELPER_DIR:-$HOME/.config/tmux}.
# When installed via TPM, install.sh sets HUNTERMARK_HELPER_DIR to the plugin's scripts/ dir.

: "${HUNTERMARK_HELPER_DIR:=$HOME/.config/tmux}"
: "${HUNTERMARK_HELP_FILE:=$HOME/.config/tmux/huntermark-help.txt}"

# Convert a list of args (m1 m2 / 1 2 / m1,m2) into the canonical mN,mN form
# that mark-pin.sh / mark-remove.sh expect. Internal helper.
_mark_args_to_csv() {
  local out="" tok arg
  for arg in "$@"; do
    for tok in ${(s:,:)arg}; do
      tok="${tok#m}"
      [[ "$tok" =~ ^[0-9]+$ ]] && out="${out}${out:+,}m${tok}"
    done
  done
  printf '%s' "$out"
}

mark() {
  if [ "$#" -eq 0 ]; then
    if [ ! -r "$HOME/.tmux/marks.sh" ]; then
      echo "no marks set" >&2
      return 1
    fi
    source "$HOME/.tmux/marks.sh"

    # Detect whether any mark has a _host field, so we can drop the HOST
    # column when no AD-shaped marks exist (keeps the narrow case tidy).
    local has_host=0 v
    for v in ${(ko)parameters}; do
      case "$v" in m<->_host) has_host=1; break ;; esac
    done

    {
      if [ "$has_host" -eq 1 ]; then
        printf 'INDEX\tNAME\tIP\tHOST\tPIN\n'
      else
        printf 'INDEX\tNAME\tIP\tPIN\n'
      fi
      local n name ip host pinned full var_full var_ip var_host var_pin pin_mark
      for var_full in ${(ko)parameters}; do
        case "$var_full" in m<->_full) ;; *) continue ;; esac
        n="${var_full#m}"; n="${n%_full}"
        var_ip="m${n}"
        var_host="m${n}_host"
        var_pin="m${n}_pinned"
        ip="${(P)var_ip}"
        host="${(P)var_host:-}"
        pinned="${(P)var_pin:-}"
        full="${(P)var_full}"
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
    pin)
      shift
      local csv
      csv=$(_mark_args_to_csv "$@")
      if [ -z "$csv" ]; then
        # No args -> list current pin state
        if [ ! -r "$HOME/.tmux/marks.sh" ]; then
          echo "no marks set" >&2; return 1
        fi
        source "$HOME/.tmux/marks.sh"
        local var pn pinned_list=""
        for var in ${(ko)parameters}; do
          case "$var" in m<->_pinned)
            [ "${(P)var}" = "1" ] || continue
            pn="${var%_pinned}"
            pinned_list="${pinned_list}${pinned_list:+, }${pn}"
            ;;
          esac
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
    for v in ${(k)parameters}; do
      case "$v" in m<->|m<->_full|m<->_host|m<->_pinned) unset "$v" ;; esac
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
  case "$n" in m<->) ;; *) echo "expected mN (e.g. m1, m2)" >&2; return 1 ;; esac
  [ -r "$HOME/.tmux/marks.sh" ] && source "$HOME/.tmux/marks.sh" 2>/dev/null
  local val="${(P)n}"
  [ -z "$val" ] && { echo "$n not set" >&2; return 1; }
  printf '%s' "$val"
}

# Resolve mN -> hostname. Prefers $mN_host, falls back to $mN. Fails if the
# resolved value contains no letters (i.e. it's an IPv4) — Kerberos-aware
# tools like kinit/evil-winrm/secretsdump -k will reject a bare IP, and a
# silent IP-substitute would just produce confusing tool errors downstream.
mhost() {
  local n="$1"
  case "$n" in m<->) ;; *) echo "expected mN (e.g. m1, m2)" >&2; return 1 ;; esac
  [ -r "$HOME/.tmux/marks.sh" ] && source "$HOME/.tmux/marks.sh" 2>/dev/null
  local host_var="${n}_host"
  local host="${(P)host_var:-${(P)n}}"
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

# precmd hook: source ~/.tmux/marks.sh on every prompt so $mN propagates across panes
_zero_load_marks() {
  [ -r "$HOME/.tmux/marks.sh" ] && source "$HOME/.tmux/marks.sh" 2>/dev/null
}
typeset -ga precmd_functions
[[ "${precmd_functions[(r)_zero_load_marks]}" != "_zero_load_marks" ]] && precmd_functions+=(_zero_load_marks)
