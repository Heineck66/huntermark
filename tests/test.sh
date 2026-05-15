#!/bin/bash
# HunterMark v2 — test suite
# Each test runs in an isolated $HOME (mktemp -d). No tmux required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
SHELL_DIR="$(cd "$(dirname "$0")/../shell" && pwd)"

pass=0 fail=0 total=0
failures=()

# ── Helpers ──────────────────────────────────────────────────────────────────

_setup() {
  TEST_HOME=$(mktemp -d)
  mkdir -p "$TEST_HOME/.tmux"
}

_teardown() {
  rm -rf "$TEST_HOME"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  total=$((total + 1))
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("FAIL: $label\n  expected: '$expected'\n  actual:   '$actual'")
    printf "  FAIL: %s\n" "$label"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  total=$((total + 1))
  if echo "$haystack" | grep -qF "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("FAIL: $label\n  expected to contain: '$needle'\n  got: '$haystack'")
    printf "  FAIL: %s\n" "$label"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  total=$((total + 1))
  if echo "$haystack" | grep -qF "$needle"; then
    fail=$((fail + 1))
    failures+=("FAIL: $label\n  expected NOT to contain: '$needle'\n  got: '$haystack'")
    printf "  FAIL: %s\n" "$label"
  else
    pass=$((pass + 1))
  fi
}

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  total=$((total + 1))
  if [ "$expected" -eq "$actual" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("FAIL: $label\n  expected exit: $expected\n  actual exit:   $actual")
    printf "  FAIL: %s\n" "$label"
  fi
}

# Source marks.sh in a clean subshell, print the value of a var
_read_var() {
  local home="$1" var="$2"
  (
    for v in $(compgen -v 2>/dev/null | grep -E '^m[0-9]+(_full|_host|_pinned)?$'); do unset "$v"; done
    source "$home/.tmux/marks.sh" 2>/dev/null
    printf '%s' "${!var:-}"
  )
}

_mark_count() {
  local home="$1"
  [ -r "$home/.tmux/marks.sh" ] || { echo 0; return; }
  grep -c '^export m[0-9]\+=' "$home/.tmux/marks.sh" 2>/dev/null || echo 0
}

section() {
  printf "\n── %s ──\n" "$1"
}

# ── 1. Validator (mark-set.sh) ───────────────────────────────────────────────

section "Validator — input parsing"

# 1a. IPv4 only
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
assert_eq "ipv4: m1 value" "10.10.10.42" "$(_read_var "$TEST_HOME" m1)"
assert_eq "ipv4: m1_full" "Forge 10.10.10.42" "$(_read_var "$TEST_HOME" m1_full)"
assert_eq "ipv4: m1_host empty" "" "$(_read_var "$TEST_HOME" m1_host)"
_teardown

# 1b. FQDN only (no IP)
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "WebApp webapp.htb" 2>/dev/null
assert_eq "fqdn-only: m1 value" "webapp.htb" "$(_read_var "$TEST_HOME" m1)"
assert_eq "fqdn-only: m1_host empty" "" "$(_read_var "$TEST_HOME" m1_host)"
_teardown

# 1c. IPv4 + FQDN → IP primary, FQDN secondary
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
assert_eq "ip+fqdn: m1=IP" "10.10.10.40" "$(_read_var "$TEST_HOME" m1)"
assert_eq "ip+fqdn: m1_host=FQDN" "dc01.lab.local" "$(_read_var "$TEST_HOME" m1_host)"
_teardown

# 1d. NetBIOS single-label hostname
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 DC01" 2>/dev/null
assert_eq "netbios: m1 value" "DC01" "$(_read_var "$TEST_HOME" m1)"
_teardown

# 1e. Single-label with name≠target (last token wins)
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "WS01 DC02" 2>/dev/null
assert_eq "single-label last-token: m1=DC02" "DC02" "$(_read_var "$TEST_HOME" m1)"
_teardown

# 1f. Reject garbage — no IP, no hostname
_setup
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "---" 2>/dev/null || rc=$?
assert_exit "reject garbage" 1 "$rc"
assert_eq "reject garbage: no marks" "0" "$(_mark_count "$TEST_HOME")"
_teardown

# 1g. Reject --help (no leading-dash hostnames)
_setup
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "--help" 2>/dev/null || rc=$?
assert_exit "reject --help" 1 "$rc"
_teardown

# 1h. Reject pure digits (no letters → not a hostname)
_setup
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "123" 2>/dev/null || rc=$?
assert_exit "reject pure digits" 1 "$rc"
_teardown

# 1i. Sequential index
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "B 10.0.0.2" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "C 10.0.0.3" 2>/dev/null
assert_eq "sequential: m1" "10.0.0.1" "$(_read_var "$TEST_HOME" m1)"
assert_eq "sequential: m2" "10.0.0.2" "$(_read_var "$TEST_HOME" m2)"
assert_eq "sequential: m3" "10.0.0.3" "$(_read_var "$TEST_HOME" m3)"
_teardown

# ── 2. Duplicate detection ───────────────────────────────────────────────────

section "Duplicate detection"

# 2a. Same IP → rejected
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge2 10.10.10.42" 2>/dev/null || rc=$?
assert_exit "dup IP rejected" 1 "$rc"
assert_eq "dup IP: still 1 mark" "1" "$(_mark_count "$TEST_HOME")"
_teardown

# 2b. Same FQDN → rejected
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC02 10.10.10.41 dc01.lab.local" 2>/dev/null || rc=$?
assert_exit "dup FQDN rejected" 1 "$rc"
_teardown

# 2c. Case-insensitive host match → rejected
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC02 10.10.10.41 DC01.LAB.LOCAL" 2>/dev/null || rc=$?
assert_exit "dup case-insensitive host rejected" 1 "$rc"
_teardown

# 2d. IP matches existing mN_host → rejected
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 DC01" 2>/dev/null
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC02 dc01" 2>/dev/null || rc=$?
assert_exit "dup single-label host rejected" 1 "$rc"
_teardown

# 2e. Different targets → accepted
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Devbox 10.10.10.99" 2>/dev/null
assert_eq "different IPs: 2 marks" "2" "$(_mark_count "$TEST_HOME")"
_teardown

# 2f. New IP matching existing _host → rejected
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Other dc01.lab.local" 2>/dev/null || rc=$?
assert_exit "new host matches existing _host" 1 "$rc"
_teardown

# ── 3. Pin / unpin ──────────────────────────────────────────────────────────

section "Pin / unpin"

# 3a. Pin sets mN_pinned=1
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
assert_eq "pin: m1_pinned=1" "1" "$(_read_var "$TEST_HOME" m1_pinned)"
_teardown

# 3b. Pin is idempotent (no duplicate lines)
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
count=$(grep -c 'export m1_pinned=' "$TEST_HOME/.tmux/marks.sh")
assert_eq "pin idempotent: single line" "1" "$count"
_teardown

# 3c. Unpin removes mN_pinned
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" --unset 2>/dev/null
assert_eq "unpin: m1_pinned gone" "" "$(_read_var "$TEST_HOME" m1_pinned)"
_teardown

# 3d. Pin multiple at once
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "B 10.0.0.2" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1,m2" 2>/dev/null
assert_eq "pin multi: m1_pinned" "1" "$(_read_var "$TEST_HOME" m1_pinned)"
assert_eq "pin multi: m2_pinned" "1" "$(_read_var "$TEST_HOME" m2_pinned)"
_teardown

# 3e. Pin nonexistent mark → skipped (no crash)
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m99" 2>/dev/null || rc=$?
assert_eq "pin nonexistent: exit 0" "0" "$rc"
_teardown

# 3f. Pin logs to history
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
last_op=$(tail -1 "$TEST_HOME/.tmux/marks-history.log" | cut -f2)
assert_eq "pin: history entry" "pin" "$last_op"
_teardown

# ── 4. Status bar rendering (mark-status.sh) ────────────────────────────────

section "Status bar rendering"

# 4a. Single mark → one chip, no overflow
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
out=$(HOME="$TEST_HOME" "$SCRIPT_DIR/mark-status.sh" 2>/dev/null || true)
assert_contains "single mark: has m1:" "m1:" "$out"
assert_not_contains "single mark: no overflow" "(+" "$out"
_teardown

# 4b. 4 marks, max=3 → 3 chips + (+1)
_setup
for i in 1 2 3 4; do
  HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Box$i 10.0.0.$i" 2>/dev/null
done
out=$(HOME="$TEST_HOME" "$SCRIPT_DIR/mark-status.sh" 2>/dev/null || true)
assert_contains "overflow: has (+1)" "(+1)" "$out"
_teardown

# 4c. 5 marks, max=3 → (+2)
_setup
for i in 1 2 3 4 5; do
  HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Box$i 10.0.0.$i" 2>/dev/null
done
out=$(HOME="$TEST_HOME" "$SCRIPT_DIR/mark-status.sh" 2>/dev/null || true)
assert_contains "5 marks: has (+2)" "(+2)" "$out"
_teardown

# 4d. Pin oldest → pinned appears in visible set, bumps unpinned
_setup
for i in 1 2 3 4 5; do
  HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Box$i 10.0.0.$i" 2>/dev/null
done
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
out=$(HOME="$TEST_HOME" "$SCRIPT_DIR/mark-status.sh" 2>/dev/null || true)
assert_contains "pin oldest visible: has m1:" "m1:" "$out"
assert_contains "pin oldest visible: has (+2)" "(+2)" "$out"
_teardown

# 4e. Pin 3 of 5 → those 3 pinned shown, (+2) for unpinned
_setup
for i in 1 2 3 4 5; do
  HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Box$i 10.0.0.$i" 2>/dev/null
done
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1,m2,m3" 2>/dev/null
out=$(HOME="$TEST_HOME" "$SCRIPT_DIR/mark-status.sh" 2>/dev/null || true)
assert_contains "3 pinned: has m1:" "m1:" "$out"
assert_contains "3 pinned: has m2:" "m2:" "$out"
assert_contains "3 pinned: has m3:" "m3:" "$out"
assert_contains "3 pinned: (+2)" "(+2)" "$out"
_teardown

# 4f. No marks → empty output
_setup
out=$(HOME="$TEST_HOME" "$SCRIPT_DIR/mark-status.sh" 2>/dev/null || true)
assert_eq "no marks: empty" "" "$out"
_teardown

# 4g. Pinned chip uses different style than unpinned
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "B 10.0.0.2" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
out=$(HOME="$TEST_HOME" "$SCRIPT_DIR/mark-status.sh" 2>/dev/null || true)
assert_contains "pinned style: cyan" "fg=cyan" "$out"
_teardown

# ── 5. Edit (mark-edit.sh) ──────────────────────────────────────────────────

section "Edit"

# 5a. Basic edit changes value
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-edit.sh" m1 "Forge 10.10.10.99" 2>/dev/null
assert_eq "edit: new IP" "10.10.10.99" "$(_read_var "$TEST_HOME" m1)"
_teardown

# 5b. Edit preserves pin state
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-edit.sh" m1 "Forge 10.10.10.99" 2>/dev/null
assert_eq "edit preserves pin" "1" "$(_read_var "$TEST_HOME" m1_pinned)"
_teardown

# 5c. Edit adds host when new input has FQDN
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-edit.sh" m1 "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
assert_eq "edit adds host: IP" "10.10.10.40" "$(_read_var "$TEST_HOME" m1)"
assert_eq "edit adds host: host" "dc01.lab.local" "$(_read_var "$TEST_HOME" m1_host)"
_teardown

# 5d. Edit drops host when new input has no FQDN
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-edit.sh" m1 "Forge 10.10.10.42" 2>/dev/null
assert_eq "edit drops host: IP" "10.10.10.42" "$(_read_var "$TEST_HOME" m1)"
assert_eq "edit drops host: host gone" "" "$(_read_var "$TEST_HOME" m1_host)"
_teardown

# 5e. Edit dedup exempts self (can keep same IP)
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-edit.sh" m1 "NewName 10.10.10.42" 2>/dev/null || rc=$?
assert_exit "edit self-exempt: succeeds" 0 "$rc"
_teardown

# 5f. Edit dedup catches collision with OTHER mark
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Devbox 10.10.10.99" 2>/dev/null
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-edit.sh" m1 "Forge 10.10.10.99" 2>/dev/null || rc=$?
assert_exit "edit dup with other: rejected" 1 "$rc"
assert_eq "edit dup: value unchanged" "10.10.10.42" "$(_read_var "$TEST_HOME" m1)"
_teardown

# 5g. Edit nonexistent mark → error
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-edit.sh" m99 "X 10.0.0.1" 2>/dev/null || rc=$?
assert_exit "edit nonexistent: rejected" 1 "$rc"
_teardown

# ── 6. Remove (mark-remove.sh) ──────────────────────────────────────────────

section "Remove"

# 6a. Remove single mark
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "B 10.0.0.2" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m1" 2>/dev/null
assert_eq "remove m1: gone" "" "$(_read_var "$TEST_HOME" m1)"
assert_eq "remove m1: m2 intact" "10.0.0.2" "$(_read_var "$TEST_HOME" m2)"
_teardown

# 6b. Remove strips all 4 fields (_host, _pinned, _full)
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m1" 2>/dev/null
remaining=$(cat "$TEST_HOME/.tmux/marks.sh" 2>/dev/null || true)
assert_eq "remove: marks.sh empty" "" "$remaining"
_teardown

# 6c. Remove pushes to trash
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m1" 2>/dev/null
assert_contains "remove: trash has entry" "export m1=" "$(cat "$TEST_HOME/.tmux/marks-trash.sh" 2>/dev/null)"
_teardown

# 6d. Trash includes _host and _pinned
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m1" 2>/dev/null
trash=$(cat "$TEST_HOME/.tmux/marks-trash.sh" 2>/dev/null)
assert_contains "trash: has m1_host" "m1_host=" "$trash"
assert_contains "trash: has m1_pinned" "m1_pinned=" "$trash"
_teardown

# 6e. Remove multiple (csv)
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "B 10.0.0.2" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "C 10.0.0.3" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m1,m3" 2>/dev/null
assert_eq "remove csv: m1 gone" "" "$(_read_var "$TEST_HOME" m1)"
assert_eq "remove csv: m2 intact" "10.0.0.2" "$(_read_var "$TEST_HOME" m2)"
assert_eq "remove csv: m3 gone" "" "$(_read_var "$TEST_HOME" m3)"
_teardown

# 6f. Remove all
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "B 10.0.0.2" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "all" 2>/dev/null
assert_eq "remove all: marks.sh gone" "false" "$([ -f "$TEST_HOME/.tmux/marks.sh" ] && echo true || echo false)"
_teardown

# 6g. Remove logs to history
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m1" 2>/dev/null
last_op=$(tail -1 "$TEST_HOME/.tmux/marks-history.log" | cut -f2)
assert_eq "remove: history entry" "remove" "$last_op"
_teardown

# 6h. Numbering preserves gaps (m2 removed, m1 and m3 stay)
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "B 10.0.0.2" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "C 10.0.0.3" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m2" 2>/dev/null
assert_eq "gap: m1 intact" "10.0.0.1" "$(_read_var "$TEST_HOME" m1)"
assert_eq "gap: m2 gone" "" "$(_read_var "$TEST_HOME" m2)"
assert_eq "gap: m3 intact" "10.0.0.3" "$(_read_var "$TEST_HOME" m3)"
_teardown

# ── 7. Undo (mark-undo.sh) ──────────────────────────────────────────────────

section "Undo"

# 7a. Basic undo restores to original index
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-undo.sh" 2>/dev/null
assert_eq "undo: m1 restored" "10.0.0.1" "$(_read_var "$TEST_HOME" m1)"
_teardown

# 7b. Undo restores _host and _pinned
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-undo.sh" 2>/dev/null
assert_eq "undo: m1 IP" "10.10.10.40" "$(_read_var "$TEST_HOME" m1)"
assert_eq "undo: m1_host" "dc01.lab.local" "$(_read_var "$TEST_HOME" m1_host)"
assert_eq "undo: m1_pinned" "1" "$(_read_var "$TEST_HOME" m1_pinned)"
_teardown

# 7c. Undo with index conflict → next free index
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "B 10.0.0.2" 2>/dev/null  # takes m1
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-undo.sh" 2>/dev/null
assert_eq "undo conflict: m1 is B" "10.0.0.2" "$(_read_var "$TEST_HOME" m1)"
assert_eq "undo conflict: m2 is A" "10.0.0.1" "$(_read_var "$TEST_HOME" m2)"
_teardown

# 7d. Undo with index conflict renumbers _host and _pinned too
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "B 10.0.0.2" 2>/dev/null  # takes m1
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-undo.sh" 2>/dev/null
assert_eq "undo renumber: m2 IP" "10.10.10.40" "$(_read_var "$TEST_HOME" m2)"
assert_eq "undo renumber: m2_host" "dc01.lab.local" "$(_read_var "$TEST_HOME" m2_host)"
assert_eq "undo renumber: m2_pinned" "1" "$(_read_var "$TEST_HOME" m2_pinned)"
_teardown

# 7e. Undo on empty trash → error
_setup
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-undo.sh" 2>/dev/null || rc=$?
assert_exit "undo empty trash: error" 1 "$rc"
_teardown

# 7f. Undo logs to history
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "A 10.0.0.1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-undo.sh" 2>/dev/null
last_op=$(tail -1 "$TEST_HOME/.tmux/marks-history.log" | cut -f2)
assert_eq "undo: history entry" "undo" "$last_op"
_teardown

# ── 8. mhost (bash) ─────────────────────────────────────────────────────────

section "mhost (bash)"

# 8a. mhost returns _host when set
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
result=$(HOME="$TEST_HOME" bash -c "source '$SHELL_DIR/huntermark.bash' 2>/dev/null; mhost m1")
assert_eq "mhost: returns _host" "dc01.lab.local" "$result"
_teardown

# 8b. mhost falls back to $mN when _host is absent (and $mN contains letters)
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 DC01" 2>/dev/null
result=$(HOME="$TEST_HOME" bash -c "source '$SHELL_DIR/huntermark.bash' 2>/dev/null; mhost m1")
assert_eq "mhost: falls back to mN" "DC01" "$result"
_teardown

# 8c. mhost fails when resolved value is IPv4-only (no letters)
_setup
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
rc=0; HOME="$TEST_HOME" bash -c "source '$SHELL_DIR/huntermark.bash' 2>/dev/null; mhost m1" 2>/dev/null || rc=$?
assert_exit "mhost: rejects IPv4-only" 1 "$rc"
_teardown

# 8d. mhost fails on unset mark
_setup
rc=0; HOME="$TEST_HOME" bash -c "source '$SHELL_DIR/huntermark.bash' 2>/dev/null; mhost m99" 2>/dev/null || rc=$?
assert_exit "mhost: rejects unset" 1 "$rc"
_teardown

# 8e. mhost rejects bad input
_setup
rc=0; HOME="$TEST_HOME" bash -c "source '$SHELL_DIR/huntermark.bash' 2>/dev/null; mhost foo" 2>/dev/null || rc=$?
assert_exit "mhost: rejects non-mN" 1 "$rc"
_teardown

# ── 9. Integration — full lifecycle ─────────────────────────────────────────

section "Integration — full lifecycle"

_setup
# Create 3 marks: IP-only, IP+host, NetBIOS
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Forge 10.10.10.42" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC01 10.10.10.40 dc01.lab.local" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "DC02 DC02" 2>/dev/null

# Verify all 3
assert_eq "lifecycle: m1" "10.10.10.42" "$(_read_var "$TEST_HOME" m1)"
assert_eq "lifecycle: m2" "10.10.10.40" "$(_read_var "$TEST_HOME" m2)"
assert_eq "lifecycle: m2_host" "dc01.lab.local" "$(_read_var "$TEST_HOME" m2_host)"
assert_eq "lifecycle: m3" "DC02" "$(_read_var "$TEST_HOME" m3)"

# Dedup blocks duplicate
rc=0; HOME="$TEST_HOME" "$SCRIPT_DIR/mark-set.sh" "Other 10.10.10.42" 2>/dev/null || rc=$?
assert_exit "lifecycle: dup blocked" 1 "$rc"

# Pin m1, remove m2, undo m2
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-pin.sh" "m1" 2>/dev/null
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-remove.sh" "m2" 2>/dev/null
assert_eq "lifecycle: m2 removed" "" "$(_read_var "$TEST_HOME" m2)"
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-undo.sh" 2>/dev/null
assert_eq "lifecycle: m2 restored" "10.10.10.40" "$(_read_var "$TEST_HOME" m2)"
assert_eq "lifecycle: m2_host restored" "dc01.lab.local" "$(_read_var "$TEST_HOME" m2_host)"

# Edit m3 to IP+host
HOME="$TEST_HOME" "$SCRIPT_DIR/mark-edit.sh" m3 "DC02 10.10.10.41 dc02.lab.local" 2>/dev/null
assert_eq "lifecycle: m3 edited IP" "10.10.10.41" "$(_read_var "$TEST_HOME" m3)"
assert_eq "lifecycle: m3 edited host" "dc02.lab.local" "$(_read_var "$TEST_HOME" m3_host)"

# Status bar shows all 3 (within MAX=3 default)
out=$(HOME="$TEST_HOME" "$SCRIPT_DIR/mark-status.sh" 2>/dev/null || true)
assert_contains "lifecycle: bar has m1" "m1:" "$out"
assert_contains "lifecycle: bar has m2" "m2:" "$out"
assert_contains "lifecycle: bar has m3" "m3:" "$out"
assert_not_contains "lifecycle: no overflow" "(+" "$out"

# m1 pinned chip uses cyan style
assert_contains "lifecycle: m1 pinned style" "fg=cyan" "$out"

# History has all operations
hist_ops=$(cut -f2 "$TEST_HOME/.tmux/marks-history.log" | sort -u | tr '\n' ',')
assert_contains "lifecycle: history has add" "add," "$hist_ops"
assert_contains "lifecycle: history has remove" "remove," "$hist_ops"
assert_contains "lifecycle: history has undo" "undo," "$hist_ops"
assert_contains "lifecycle: history has pin" "pin," "$hist_ops"
assert_contains "lifecycle: history has edit" "edit," "$hist_ops"
_teardown

# ── Summary ──────────────────────────────────────────────────────────────────

printf "\n══════════════════════════════════════════\n"
printf "  %d passed, %d failed, %d total\n" "$pass" "$fail" "$total"
printf "══════════════════════════════════════════\n"

if [ "$fail" -gt 0 ]; then
  printf "\nFailures:\n"
  for f in "${failures[@]}"; do
    printf "  %b\n" "$f"
  done
  exit 1
fi
