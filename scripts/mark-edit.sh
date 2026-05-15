#!/bin/bash
# HunterMark — edits an existing mark in place. Index stays stable. Re-parses
# the new input via the same rules as mark-set.sh (ip + host extraction), so
# editing m1 from "Forge 10.10.10.42" to "DC01 10.10.10.40 dc01.lab.local"
# adds a $m1_host line; editing back to an IP-only value drops it.
#
# Usage:  mark-edit.sh m2 "DC01 10.10.10.40 dc01.lab.local"
#   $1: target index (e.g. m2)
#   $2: new full input (will be re-parsed for IP + host)
set -e

F="$HOME/.tmux/marks.sh"
HISTORY="$HOME/.tmux/marks-history.log"
mkdir -p "$HOME/.tmux"

n="$1"
new_input="$2"

case "$n" in
  m[0-9]*) ;;
  *) echo "usage: $0 mN \"new value\"" >&2; exit 1 ;;
esac
[ -z "$new_input" ] && { echo "empty value; use unmark to remove" >&2; exit 1; }
[ -r "$F" ] || { echo "no marks file; use mark to create" >&2; exit 1; }

if ! grep -qE "^export ${n}=" "$F"; then
  echo "$n not set" >&2
  exit 1
fi

# Same parse logic as mark-set.sh. Keep them in sync.
new_ip=$(echo "$new_input" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
input_no_ip="$new_input"
[ -n "$new_ip" ] && input_no_ip="${new_input//$new_ip/}"
new_host=$(echo "$input_no_ip" | grep -oE '[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+' | head -1)
if [ -z "$new_ip" ] && [ -z "$new_host" ]; then
  # Take LAST single-label token — see mark-set.sh for the rationale.
  for tok in $input_no_ip; do
    if [[ "$tok" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] && [[ "$tok" =~ [A-Za-z] ]]; then
      new_host="$tok"
    fi
  done
fi

new_primary=""
new_secondary=""
if [ -n "$new_ip" ]; then
  new_primary="$new_ip"
  new_secondary="$new_host"
elif [ -n "$new_host" ]; then
  new_primary="$new_host"
fi

if [ -z "$new_primary" ]; then
  msg="mark edit: missing ip/hostname (got: ${new_input})"
  echo "$msg" >&2
  tmux display-message "$msg" 2>/dev/null || true
  exit 1
fi

# Duplicate detection — same logic as mark-set.sh but skip the mark being
# edited. Scrub stale env first.
for _stale in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+(_full|_host|_pinned)?$'); do
  unset "$_stale"
done
unset _stale
# shellcheck disable=SC1090
source "$F" 2>/dev/null || true

primary_lc="${new_primary,,}"
secondary_lc="${new_secondary,,}"

dup_idx=""
dup_target=""
for var in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+$' | sort -V); do
  [ "$var" = "$n" ] && continue   # don't collide with self
  existing_val="${!var}"
  existing_val_lc="${existing_val,,}"
  host_var="${var}_host"
  existing_host="${!host_var:-}"
  existing_host_lc="${existing_host,,}"

  for needle in "$primary_lc" "$secondary_lc"; do
    [ -z "$needle" ] && continue
    if [ "$needle" = "$existing_val_lc" ] || { [ -n "$existing_host_lc" ] && [ "$needle" = "$existing_host_lc" ]; }; then
      dup_idx="$var"
      if [ -n "$existing_host" ]; then
        dup_target="${existing_val} / ${existing_host}"
      else
        dup_target="${existing_val}"
      fi
      break 2
    fi
  done
done

if [ -n "$dup_idx" ]; then
  msg="mark edit: would duplicate ${dup_idx} (${dup_target})"
  echo "$msg" >&2
  tmux display-message "$msg" 2>/dev/null || true
  exit 1
fi

# Rewrite the file: replace mN= and mN_full=, add/replace/drop mN_host=,
# preserve mN_pinned= and everything for other marks.
#
# Bookkeeping: when we see mN_full, emit the new _host line right after if
# the new input has a host (so the host line lives in its canonical slot
# even if it wasn't there before). Drop any existing _host line so we don't
# double-emit.
{
  host_emitted=0
  while IFS= read -r line; do
    case "$line" in
      "export ${n}="*)
        printf 'export %s=%q\n' "$n" "$new_primary"
        ;;
      "export ${n}_full="*)
        printf 'export %s_full=%q\n' "$n" "$new_input"
        if [ -n "$new_secondary" ] && [ "$host_emitted" -eq 0 ]; then
          printf 'export %s_host=%q\n' "$n" "$new_secondary"
          host_emitted=1
        fi
        ;;
      "export ${n}_host="*)
        # Drop the original; we've either emitted a replacement after _full
        # already, or the new input has no host and the line should disappear.
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done < "$F"
} > "${F}.new"
mv "${F}.new" "$F"

ts=$(date -Iseconds)
printf "%s\tedit\t%s\t%s\n" "$ts" "$n" "$new_input" >> "$HISTORY"

"${0%/*}/mark-status.sh" >/dev/null 2>&1 || true
tmux refresh-client -S 2>/dev/null || true
if [ -t 1 ]; then
  if [ -n "$new_secondary" ]; then
    echo "edited ${n}=${new_primary} (host: ${new_secondary})"
  else
    echo "edited ${n}=${new_primary}"
  fi
fi
