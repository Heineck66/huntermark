#!/bin/bash
# HunterMark — adds a mark.
# Input source (in order):
#   1. Command-line arg ($1) — used by the `mark` shell function
#   2. Tmux user option @mark-input — used by the `prefix + t` binding
#
# Parse rules:
#   - First IPv4 in the input becomes the primary target ($mN).
#   - If the input also contains a multi-label hostname (e.g. dc01.lab.local),
#     it is stored as the secondary target ($mN_host). The IP wins the primary
#     slot because IP routing works in every tool; hostnames matter for
#     Kerberos/SMB which are AD-specific.
#   - If the input has no IPv4 but has a multi-label hostname, the hostname
#     becomes $mN. $mN_host is left unset (it would duplicate $mN).
#   - If the input has neither IPv4 nor multi-label hostname, a single-label
#     hostname (RFC 1035 label, alnum/dash, ≤63 chars, contains a letter) is
#     accepted as $mN. This unlocks NetBIOS-only AD workflows like
#     `mark DC01 DC01`. The single-label fallback is intentionally narrow so
#     that `mark Forge 10.10.10.42` does not store "Forge" as a hostname.
#
# Duplicate detection:
#   - Rejects if the new ip or host matches any existing mark's $mN or
#     $mN_host (case-insensitive for hostnames).
#   - Logs the add operation to ~/.tmux/marks-history.log
set -e

MARKS_FILE="$HOME/.tmux/marks.sh"
HISTORY_FILE="$HOME/.tmux/marks-history.log"
mkdir -p "$HOME/.tmux"

input="$1"
if [ -z "$input" ]; then
  input=$(tmux show-option -gv @mark-input 2>/dev/null || true)
fi
tmux set-option -gu @mark-input >/dev/null 2>&1 || true

[ -z "$input" ] && exit 0

# Extract IPv4
ip=$(echo "$input" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)

# Extract multi-label hostname from input minus the IP we just took
input_no_ip="$input"
[ -n "$ip" ] && input_no_ip="${input//$ip/}"
host=$(echo "$input_no_ip" | grep -oE '[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+' | head -1)

# If still empty AND no IP either, fall back to single-label hostname. Skipped
# when an IP is present so "Forge 10.10.10.42" doesn't store "Forge" as host.
#
# We take the LAST matching token (not the first) because the input convention
# is "<name> <target>": with `mark WS01 DC01` the user means name=WS01 and
# the routing target is DC01, so DC01 wins. The single-token case
# (`mark Forge` -> primary=Forge) and the same-token-twice case
# (`mark DC01 DC01` -> primary=DC01) work naturally with either rule.
if [ -z "$ip" ] && [ -z "$host" ]; then
  for tok in $input_no_ip; do
    if [[ "$tok" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] && [[ "$tok" =~ [A-Za-z] ]]; then
      host="$tok"
    fi
  done
fi

# Decide primary vs secondary
primary=""
secondary=""
if [ -n "$ip" ]; then
  primary="$ip"
  secondary="$host"   # may be empty
elif [ -n "$host" ]; then
  primary="$host"
  secondary=""
fi

if [ -z "$primary" ]; then
  msg="mark: missing ip/hostname (got: ${input})"
  echo "$msg" >&2
  echo "usage: mark <name> <ip-or-hostname>" >&2
  tmux display-message "$msg" 2>/dev/null || true
  exit 1
fi

# Duplicate detection: source marks.sh and inspect existing $mN / $mN_host
# values. Scrub any inherited mN* env vars first so a stale shell var can't
# masquerade as an existing mark.
for _stale in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+(_full|_host|_pinned)?$'); do
  unset "$_stale"
done
unset _stale

if [ -r "$MARKS_FILE" ]; then
  # shellcheck disable=SC1090
  source "$MARKS_FILE" 2>/dev/null || true
fi

primary_lc="${primary,,}"
secondary_lc="${secondary,,}"

dup_idx=""
dup_target=""
for var in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+$' | sort -V); do
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
  msg="mark: duplicate of ${dup_idx} (${dup_target})"
  echo "$msg" >&2
  echo "use \`mark edit ${dup_idx} ...\` to update it, or \`unmark ${dup_idx}\` first" >&2
  tmux display-message "$msg" 2>/dev/null || true
  exit 1
fi

# Determine next free index based on what's on disk (compgen reflects the
# current shell, which we just sourced from, but use the file as the source
# of truth to avoid edge cases).
next=1
if [ -r "$MARKS_FILE" ]; then
  max=$(grep -oE '^export m[0-9]+=' "$MARKS_FILE" 2>/dev/null \
        | sed 's/export m//; s/=//' \
        | sort -n | tail -1)
  [ -n "$max" ] && next=$((max + 1))
fi

# Write
{
  printf "export m%d=%q\n"      "$next" "$primary"
  printf "export m%d_full=%q\n" "$next" "$input"
  [ -n "$secondary" ] && printf "export m%d_host=%q\n" "$next" "$secondary"
} >> "$MARKS_FILE"

ts=$(date -Iseconds)
printf "%s\tadd\tm%d\t%s\n" "$ts" "$next" "$input" >> "$HISTORY_FILE"

"${0%/*}/mark-status.sh" >/dev/null 2>&1 || true
tmux refresh-client -S 2>/dev/null || true
if [ -t 1 ]; then
  if [ -n "$secondary" ]; then
    echo "marked m${next}=${primary} (host: ${secondary})"
  else
    echo "marked m${next}=${primary}"
  fi
fi
