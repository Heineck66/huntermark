# HunterMark — architecture

## Pieces

```
┌──────────────────────────────────────────────────────────────────────┐
│                              tmux side                               │
│                                                                      │
│   huntermark.tmux  (TPM entrypoint)                                  │
│        │                                                             │
│        ├──► binds prefix+t       ─►  command-prompt ─► @mark-input   │
│        │                                  └──► run-shell mark-set.sh │
│        │                                                             │
│        ├──► binds prefix+M-t     ─►  command-prompt ─► @mark-remove  │
│        │                                  └──► run-shell mark-remove │
│        │                                                             │
│        ├──► binds prefix+M-h     ─►  display-popup ─► less help.txt  │
│        │                                                             │
│        └──► binds prefix+m       ─►  display-popup ─► mark-popup.sh  │
│                                                                      │
│   scripts/mark-status.sh  (re-run by every mutation script)          │
│        ├──► reads ~/.tmux/marks.sh                                   │
│        ├──► writes the chip string to @huntermark-bar (tmux opt)     │
│        └──► also prints to stdout (legacy #() callers still work)    │
│                                                                      │
│   scripts/mark-pin.sh    (set/unset mN_pinned; refreshes chip)       │
│   scripts/mark-popup.sh  (REPL: list all marks, pin/unpin live)      │
└──────────────────────────────────────────────────────────────────────┘
                                 ▲
                                 │ writes
                                 │
┌──────────────────────────────────────────────────────────────────────┐
│                          state file                                  │
│                                                                      │
│   ~/.tmux/marks.sh                                                   │
│       # Required, one set per mark:                                  │
│       export m1=10.10.10.40                                          │
│       export m1_full=DC01\ 10.10.10.40\ dc01.lab.local               │
│       # Optional, written when applicable:                           │
│       export m1_host=dc01.lab.local        # explicit FQDN           │
│       export m1_pinned=1                   # sticky on the bar       │
│       ...                                                            │
└──────────────────────────────────────────────────────────────────────┘
                                 ▲
                                 │ sources every prompt
                                 │
┌──────────────────────────────────────────────────────────────────────┐
│                            shell side                                │
│                                                                      │
│   ~/.bashrc  or  ~/.zshrc                                            │
│        │                                                             │
│        └──► sources shell/huntermark.{bash,zsh}                      │
│                  ├── functions: mark, unmark, mark pin/unpin         │
│                  ├── functions: mssh, mnmap, mcurl, mping, mhost     │
│                  ├── internal:  _mark_resolve, _mark_args_to_csv     │
│                  └── precmd hook: _zero_load_marks                   │
│                          ↑                                           │
│             fires every prompt; sources marks.sh                     │
└──────────────────────────────────────────────────────────────────────┘
```

## Data flow

### Data model

| Field | Required | Set when | Used for |
|---|---|---|---|
| `mN` | yes | always | Primary target. IPv4 if input contains one, otherwise hostname. The `mssh`/`mnmap`/`mcurl`/`mping` wrappers route to this value. |
| `mN_full` | yes | always | Raw input as the user typed it. Drives the "NAME" column in the table view by subtracting the parsed IP and host. |
| `mN_host` | no | input has both an IPv4 and a multi-label hostname | Kerberos / SMB workflows that reject bare IPs. Exposed via `mhost mN`. |
| `mN_pinned` | no | user pinned the mark (`mark pin mN`) | Render rule: pinned marks always occupy bar slots; unpinned fill remaining slots by recency. |

### Input parse rules (`scripts/mark-set.sh`)

1. First IPv4 in the input wins the primary slot (`$mN`).
2. If input also has a multi-label hostname (e.g. `dc01.lab.local`), it becomes `$mN_host`.
3. With no IPv4: a multi-label hostname becomes the primary; `$mN_host` stays unset.
4. With neither: a single-label NetBIOS-style hostname is accepted as primary (last matching token wins, to support `<name> <host>` convention like `WS01 DC01`).
5. Inputs matching none of the above are rejected; nothing is written.

### Adding a mark via `prefix + t`

1. User hits `prefix + t` → tmux opens `command-prompt -p 'mark target:'`
2. User types `DC01 10.10.10.40 dc01.lab.local`, hits Enter
3. Tmux substitutes `%%` into the template: `set -g @mark-input '…' ; run-shell -b $PLUGIN/scripts/mark-set.sh`
4. `mark-set.sh` reads `@mark-input`, parses ip + host per the rules above, checks for duplicates by IP/hostname against existing `$mN`/`$mN_host` (rejecting on collision), computes next free index N, appends `export mN=...`, `export mN_full=...`, and optionally `export mN_host=...` to `~/.tmux/marks.sh`, then refreshes the chip via `mark-status.sh` + `refresh-client`.
5. On next prompt in any open shell, the precmd hook sources `~/.tmux/marks.sh` → `$mN` is now defined in that shell

### Adding a mark via the shell

1. User types `mark Forge 10.10.10.42`
2. The `mark` function calls `$HUNTERMARK_HELPER_DIR/mark-set.sh` with the input as arg
3. Same script logic as above
4. Function then `source`s `~/.tmux/marks.sh` immediately, so `$mN` is set in the current shell without waiting for the next prompt

### Why a precmd hook?

A user might add a mark in pane A, then run `mssh m2` in pane B that's been open for an hour. Pane B's shell doesn't know about the new mark unless something brings it in. The precmd hook (called once before each prompt) sources `~/.tmux/marks.sh` cheaply — sub-millisecond cost — making `$mN` always-fresh in every interactive shell.

### Why store in `~/.tmux/marks.sh` (not stdin or env)?

- **stdin**: ephemeral. Doesn't survive process or shell restarts.
- **env vars set in tmux server**: tmux's `set-environment -g` only propagates to *new* shells, not running ones. Doesn't refresh on existing prompts.
- **A file sourced by precmd**: any shell at any prompt sees the latest state. Cheap. Survives reboots. Inspectable. Greppable. Diffable.

## Idempotency contracts

- `mark-set.sh` always picks `max(existing N) + 1`; never reuses indices. Safe under concurrent appends within tmux's command serialization.
- `mark-remove.sh` rewrites the file via grep+filter; never appends. Safe to run repeatedly.
- `install.sh` checks for a tag string before appending to rc; safe to re-run.

## Chip update model

Two ways to wire the chip into `status-right`:

- **Push (recommended): `#{@huntermark-bar}`.** Every mutation script (`mark-set`, `mark-remove`, `mark-edit`, `mark-undo`, `mark-pin`) calls `mark-status.sh` at the end, which recomputes the chip string and writes it to the `@huntermark-bar` user option. `refresh-client -S` then redraws the status bar — so removals, edits, and pin toggles reflect immediately, no polling lag.
- **Pull (legacy): `#(mark-status.sh)`.** Tmux re-executes `#()` shell formats on `status-interval` cadence (default 5 s) and caches the output between runs, so a removal can linger on the bar until the next tick. Still supported because `mark-status.sh` continues to print its result to stdout alongside writing the option.

### Render rule

1. Partition marks into pinned (`$mN_pinned == 1`) and unpinned.
2. Concatenate: pinned (sorted ascending by N) ++ unpinned (sorted descending by N — newest first).
3. Take the first `@huntermark-max-chips` entries (default 3) as the visible set.
4. Sort the visible set ascending by N for a stable left-to-right layout.
5. Render each chip in the visible set; pinned chips use `@huntermark-style-pin` for the index.
6. If `total - visible > 0`, append a `(+X)` overflow chip in `@huntermark-style-overflow`.

## Performance

- Helpers run in <50 ms typically. With the push model the chip only re-renders on actual mutations, so steady-state cost is zero.
- The precmd hook does `[ -r FILE ] && source FILE` — fast path is a stat call (microseconds), slow path is sourcing ~1 KB of shell. Negligible.

## Limitations / future work

The current schema (`mN`, `mN_full`, `mN_host`, `mN_pinned`) is open-ended — additional optional fields like `mN_os`, `mN_ports`, `mN_notes`, or `mN_creds` could plug into the same per-mark file without breaking back-compat. Known follow-ons: nmap import (`mark scan <subnet>`, `mark enrich mN`), liveness check (dim chip when host unreachable), OPSEC redact mode, by-name lookup, multi-engagement scoping.
