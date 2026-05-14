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
│        └──► binds prefix+M-h     ─►  display-popup ─► less help.txt  │
│                                                                      │
│   scripts/mark-status.sh  (re-run by every mutation script)          │
│        ├──► reads ~/.tmux/marks.sh                                   │
│        ├──► writes the chip string to @huntermark-bar (tmux opt)     │
│        └──► also prints to stdout (legacy #() callers still work)    │
└──────────────────────────────────────────────────────────────────────┘
                                 ▲
                                 │ writes
                                 │
┌──────────────────────────────────────────────────────────────────────┐
│                          state file                                  │
│                                                                      │
│   ~/.tmux/marks.sh                                                   │
│       export m1=10.10.10.42                                          │
│       export m1_full=Forge\ 10.10.10.42                              │
│       export m2=10.10.10.99                                          │
│       export m2_full=Devbox\ 10.10.10.99                             │
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
│                  ├── functions: mark, unmark                         │
│                  ├── functions: mssh, mnmap, mcurl, mping            │
│                  ├── internal:  _mark_resolve                        │
│                  └── precmd hook: _zero_load_marks                   │
│                          ↑                                           │
│             fires every prompt; sources marks.sh                     │
└──────────────────────────────────────────────────────────────────────┘
```

## Data flow

### Adding a mark via `prefix + t`

1. User hits `prefix + t` → tmux opens `command-prompt -p 'mark target:'`
2. User types `Forge 10.10.10.42`, hits Enter
3. Tmux substitutes `%%` into the template: `set -g @mark-input 'Forge 10.10.10.42' ; run-shell -b $PLUGIN/scripts/mark-set.sh`
4. `mark-set.sh` reads `@mark-input`, computes next free index N, parses IP, appends `export mN=...` and `export mN_full=...` to `~/.tmux/marks.sh`, refreshes tmux
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

- **Push (recommended): `#{@huntermark-bar}`.** Every mutation script (`mark-set`, `mark-remove`, `mark-edit`, `mark-undo`) calls `mark-status.sh` at the end, which recomputes the chip string and writes it to the `@huntermark-bar` user option. `refresh-client -S` then redraws the status bar — so removals and edits reflect immediately, no polling lag.
- **Pull (legacy): `#(mark-status.sh)`.** Tmux re-executes `#()` shell formats on `status-interval` cadence (default 5 s) and caches the output between runs, so a removal can linger on the bar until the next tick. Still supported because `mark-status.sh` continues to print its result to stdout alongside writing the option.

## Performance

- Helpers run in <50 ms typically. With the push model the chip only re-renders on actual mutations, so steady-state cost is zero.
- The precmd hook does `[ -r FILE ] && source FILE` — fast path is a stat call (microseconds), slow path is sourcing ~1 KB of shell. Negligible.

## Limitations / future work

See `notes/tmux-todo-improvement.md` (private to original author) for a backlog of possible features (pin/primary, per-target metadata, by-name lookup, OPSEC redacted mode, history log, engagement scoping, etc.). Most are clean follow-ons that fit the current file format.
