#!/bin/bash
# HunterMark — interactive marks popup. Lists every mark with index, name,
# IP, hostname, and pin state, then accepts pin/unpin/quit commands via a
# tiny REPL. Bound to `prefix + m` by default (see huntermark.tmux).
#
# Implementation choices:
#   - No external deps beyond what mark-* already uses (column, sort, grep).
#   - Each iteration re-sources marks.sh fresh so the popup reflects external
#     changes (e.g. another pane added a mark while the popup was open).
#   - Pin/unpin actions delegate to mark-pin.sh — same logging, same refresh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="$HOME/.tmux/marks.sh"

# Scrub stale vars before each render so a removed mark can't ghost in.
_scrub_marks_env() {
  local v
  for v in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+(_full|_host|_pinned)?$'); do
    unset "$v"
  done
}

draw() {
  clear
  echo "HunterMark — all marks"

  _scrub_marks_env

  if [ ! -r "$F" ]; then
    echo
    echo "  (no marks set)"
    echo
    echo "Commands:  q  quit"
    return
  fi

  # shellcheck disable=SC1090
  source "$F" 2>/dev/null

  declare -A vals hosts pinned
  local var n
  for var in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+_full$'); do
    if [[ "$var" =~ ^m([0-9]+)_full$ ]]; then
      n="${BASH_REMATCH[1]}"
      vals["$n"]="${!var}"
      local hv="m${n}_host"; hosts["$n"]="${!hv:-}"
      local pv="m${n}_pinned"; pinned["$n"]="${!pv:-}"
    fi
  done

  if [ ${#vals[@]} -eq 0 ]; then
    echo
    echo "  (no marks set)"
    echo
    echo "Commands:  q  quit"
    return
  fi

  local MAX
  MAX=$(tmux show-option -gv @huntermark-max-chips 2>/dev/null)
  [ -z "$MAX" ] && MAX=3
  case "$MAX" in *[!0-9]*) MAX=3 ;; esac

  # Compute visible set the same way mark-status.sh does.
  local -a pinned_asc unpinned_desc
  mapfile -t pinned_asc   < <(for n in "${!vals[@]}"; do [ "${pinned[$n]}" = "1" ] && echo "$n"; done | sort -n)
  mapfile -t unpinned_desc < <(for n in "${!vals[@]}"; do [ "${pinned[$n]}" != "1" ] && echo "$n"; done | sort -nr)

  local -a visible
  for n in "${pinned_asc[@]}" "${unpinned_desc[@]}"; do
    [ "${#visible[@]}" -ge "$MAX" ] && break
    visible+=("$n")
  done

  # Header row — drop HOST column when nobody has a host
  local has_host=0
  for n in "${!hosts[@]}"; do
    [ -n "${hosts[$n]}" ] && { has_host=1; break; }
  done

  echo "  (max-chips: ${MAX})"
  echo

  {
    if [ "$has_host" -eq 1 ]; then
      printf 'INDEX\tNAME\tIP\tHOST\tPIN\n'
    else
      printf 'INDEX\tNAME\tIP\tPIN\n'
    fi
    local ip host full name pin_mark
    for n in $(printf '%s\n' "${!vals[@]}" | sort -n); do
      local iv="m${n}"; ip="${!iv}"
      host="${hosts[$n]}"
      full="${vals[$n]}"
      name="$full"
      [ -n "$ip" ]   && name=$(echo "$name" | sed "s|[[:space:]]*${ip}[[:space:]]*| |g")
      [ -n "$host" ] && name=$(echo "$name" | sed "s|[[:space:]]*${host}[[:space:]]*| |gI")
      name=$(echo "$name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      [ -z "$name" ] && name='-'
      pin_mark='-'
      [ "${pinned[$n]}" = "1" ] && pin_mark='*'
      if [ "$has_host" -eq 1 ]; then
        [ -z "$host" ] && host='-'
        printf 'm%s\t%s\t%s\t%s\t%s\n' "$n" "$name" "$ip" "$host" "$pin_mark"
      else
        printf 'm%s\t%s\t%s\t%s\n' "$n" "$name" "$ip" "$pin_mark"
      fi
    done
  } | column -t -s $'\t' | sed 's/^/  /'

  echo
  local vis_list=""
  for n in $(printf '%s\n' "${visible[@]}" | sort -n); do
    vis_list+="m${n}, "
  done
  vis_list="${vis_list%, }"
  echo "  visible on bar: ${vis_list}"

  local total=${#vals[@]}
  local shown=${#visible[@]}
  local hidden=$((total - shown))
  if [ "$hidden" -gt 0 ]; then
    local hidden_list=""
    for n in $(printf '%s\n' "${!vals[@]}" | sort -n); do
      local is_vis=0 v
      for v in "${visible[@]}"; do [ "$v" = "$n" ] && is_vis=1; done
      [ "$is_vis" -eq 0 ] && hidden_list+="m${n}, "
    done
    hidden_list="${hidden_list%, }"
    echo "         hidden : ${hidden_list}"
  fi

  echo
  echo "Commands:"
  echo "  p N [M ...]   pin marks       (e.g. p 1 3)"
  echo "  u N [M ...]   unpin marks"
  echo "  q             quit popup"
}

# REPL — converts space-separated args into the comma-separated form mark-pin.sh expects.
_args_to_csv() {
  local out="" tok
  for tok in $@; do
    tok="${tok#m}"
    if [[ "$tok" =~ ^[0-9]+$ ]]; then
      out="${out}${out:+,}m${tok}"
    fi
  done
  printf '%s' "$out"
}

while true; do
  draw
  printf '> '
  IFS= read -r line || break
  set -- $line
  cmd="${1:-}"; shift 2>/dev/null || true
  case "$cmd" in
    q|quit|exit) break ;;
    p|pin)
      idx=$(_args_to_csv "$@")
      [ -n "$idx" ] && "$SCRIPT_DIR/mark-pin.sh" "$idx" >/dev/null 2>&1 || true
      ;;
    u|unpin)
      idx=$(_args_to_csv "$@")
      [ -n "$idx" ] && "$SCRIPT_DIR/mark-pin.sh" "$idx" --unset >/dev/null 2>&1 || true
      ;;
    "") : ;;
    *) echo "unknown: $cmd  (use p / u / q)"; sleep 0.8 ;;
  esac
done
