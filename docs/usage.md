# HunterMark — Usage Guide

A walk-through guide for everyday use. For the terse one-screen reference, see `help.txt` (or hit `prefix + M-h` inside tmux). For the architecture and design rationale, see `architecture.md`.

---

## 1. The mental model

You're hunting machines. Each machine you care about gets a **mark**. A mark has:

| Field | Example | Lives as |
|---|---|---|
| Index (auto-assigned) | `m1`, `m2`, ... | Numbered slot |
| Name (free text) | `Forge` | Human label |
| IP (parsed automatically) | `10.10.10.42` | What you connect to |

Behind the scenes, every mark becomes a shell variable (`$m1`, `$m2`) and shows up as a chip on your tmux status bar.

```
status bar:  m1: Forge 10.10.10.42 | m2: Devbox 10.10.10.99 | ...
shell:       $ echo $m1
             10.10.10.42
             $ echo $m1_full
             Forge 10.10.10.42
```

Older marks stay in `$mN` forever; the bar shows the most recent 3.

---

## 2. Five-minute quick start

Assuming you've already installed (TPM plugin + `install.sh` for shell side).

```bash
# Add your first mark
$ mark Forge 10.10.10.42
marked m1=10.10.10.42

# It's now a shell variable
$ echo $m1
10.10.10.42

# And on the tmux status bar (look top-right)
#                                m1: Forge 10.10.10.42

# Use the wrappers — no more retyping IPs
$ mssh m1                    # ssh root@10.10.10.42
$ mnmap m1 -sV -p 22,80      # nmap -sV -p 22,80 10.10.10.42
$ mcurl m1 -sI               # curl -sI http://10.10.10.42
$ mping m1 -c 4              # ping -c 4 10.10.10.42

# Add more
$ mark Devbox 10.10.10.99
$ mark Box3 10.10.10.55

# Show what you've got
$ mark
INDEX  NAME    IP
m1     Forge   10.10.10.42
m2     Devbox  10.10.10.99
m3     Box3    10.10.10.55

# Remove one (soft delete — recoverable)
$ unmark m1
removed: m1

# Oops, didn't mean to
$ mark undo
restored m1
```

That's the whole loop. Everything else is variations.

---

## 3. Adding marks

### From the shell

```bash
mark <free-form text containing an IP>
```

Examples:

```bash
mark Forge 10.10.10.42
mark linux-priv-root 10.10.10.99
mark "HTB-Active (kerberoastable) 10.10.10.42"
mark 10.10.10.55                      # IP only; no name
mark vpn.client.local                 # no IP — gets stored as $mN literally
```

The script picks the **first IPv4** in the input. If none, the whole input becomes `$mN`. The full input always becomes `$mN_full`.

### From inside tmux (without leaving your current pane)

Hit `prefix + t`. A prompt appears at the bottom: `mark target:`. Type the same input format as above, hit Enter. Useful when you're SSH'd into a remote box and want to mark its details without breaking flow.

---

## 4. Using marks in commands

### The wrappers

| Command | What it runs |
|---|---|
| `mssh mN [user] [ssh-flags...]` | `ssh [ssh-flags] user@$mN` (default user: `root`) |
| `mnmap mN [args...]` | `nmap [args] $mN` |
| `mcurl mN [args...]` | `curl [args] http://$mN` |
| `mping mN [args...]` | `ping [args] $mN` |

For `mssh`, the second arg is treated as the SSH username when it doesn't start with `-`; otherwise it's an ssh flag and the username defaults to `root`. Any further args pass straight to `ssh`.

```bash
mssh m1                          # ssh root@$m1
mssh m2 admin                    # ssh admin@$m2
mssh m1 -v                       # ssh -v root@$m1
mssh m2 admin -p 2222 -v         # ssh -p 2222 -v admin@$m2
mnmap m1 -sV -p-                 # nmap -sV -p- $m1
mnmap m1 --top-ports 100         # nmap --top-ports 100 $m1
mcurl m2 -sIL                    # curl -sIL http://$m2
mcurl m2 -X POST -d 'a=b' /api   # curl -X POST -d 'a=b' http://$m2/api  -- careful, last arg is appended
mping m1 -c 5                    # ping -c 5 $m1
```

### Direct variable use

The wrappers don't cover every tool, and that's fine — `$mN` and `$mN_full` work everywhere:

```bash
ftp $m2
gobuster dir -u http://$m1 -w ~/tools/wordlists/dirbuster/directory-list-2.3-medium.txt
ssh -L 8080:$m1:80 user@$m2     # tunnel
echo "Target: $m1_full" >> notes.md
nikto -h $m1
```

### Across panes

Open a new tmux pane, hit Enter (to trigger the precmd hook), and `$mN` is already set. The vars propagate automatically across all your zsh/bash panes after one prompt cycle.

---

## 5. Editing a mark

You typo'd an IP. Without edit, you'd `unmark m2` then re-add — but that gives you `m4` next, breaking your muscle memory.

```bash
mark edit m2 Devbox 10.10.10.250
edited m2=10.10.10.250
```

Index stays. Variable updates. Chip refreshes instantly when wired via `#{@huntermark-bar}` (recommended); the legacy `#(...)` form refreshes within `status-interval` (5 s).

---

## 6. Removing marks

### Single

```bash
unmark m1
```

Soft-deletes m1 to `~/.tmux/marks-trash.sh`. Recoverable via `mark undo`.

### Multiple

```bash
unmark m1,m3
```

Comma-separated, no spaces. Each goes to trash as its own deletion block.

### Everything

```bash
unmark all
really clear all 5 mark(s)? [y/N] y
removed: all
```

Confirms by default. Skip the prompt with:

```bash
unmark all -y
```

All entries land in trash.

### From inside tmux

Hit `prefix + M-t`. Prompt: `remove marks (all|mN|csv):`. Same syntax as the shell command. Single Enter to submit.

---

## 7. Undo

Restores the most recent deletion from trash:

```bash
mark undo
restored m1
```

If the original index is now occupied (because you added new marks after the deletion), it falls back to the next free index and tells you:

```bash
mark undo
  m1 taken; restoring as m4
restored m4
```

`mark undo` is single-step — call it again to pop the next-most-recent. If you `unmark all`, then `mark undo` repeatedly, you walk back through every entry one at a time.

Trash is capped at the most recent **20** deletion blocks (configurable via `HUNTERMARK_TRASH_LIMIT`).

---

## 8. History

Append-only log of every operation: add, edit, remove, undo. Each line is timestamped (ISO 8601 with timezone).

```bash
mark history          # tail of last 20
mark history 50       # tail of last 50
mark history all      # entire log
```

Format:

```
2026-05-10T19:38:54-04:00  add     m1  Forge 10.10.10.42
2026-05-10T19:39:01-04:00  add     m2  Devbox 10.10.10.99
2026-05-10T19:42:17-04:00  edit    m2  Devbox 10.10.10.250
2026-05-10T19:43:00-04:00  remove  m1  Forge 10.10.10.42
2026-05-10T19:43:30-04:00  undo    m1  Forge 10.10.10.42
```

The log lives at `~/.tmux/marks-history.log` and never auto-rotates — useful for engagement reports. Delete or archive it manually when you want a fresh slate.

---

## 9. Real-world workflows

### CTF / HTB box

```bash
# Box released, IP shown in the dashboard
mark Forge 10.10.10.42

# Initial recon
mnmap m1 -sV -p-
mcurl m1 -sI
gobuster dir -u http://$m1 -w ~/tools/wordlists/dirbuster/directory-list-2.3-medium.txt

# Get a foothold, want to ssh in repeatedly
mssh m1 www-data
# ... use the box ...
exit

# Done with the box
unmark m1
```

### Multi-box engagement

```bash
mark perimeter 10.13.5.1          # entry point
mark dc 10.13.5.10                # domain controller
mark workstation 10.13.5.150      # user box
mark fileserver 10.13.5.42        # data target

mark
INDEX  NAME         IP
m1     perimeter    10.13.5.1
m2     dc           10.13.5.10
m3     workstation  10.13.5.150
m4     fileserver   10.13.5.42

# Now jump around
mssh m2
mnmap m4 --script smb-enum-shares
mcurl m1 -sI
```

When you finish, `mark history all > engagement.log` for your report.

### Pivot

You popped m1, found internal IPs only reachable through it. Pivot:

```bash
# Set up SSH tunnel via m1 to the internal box
ssh -L 9000:10.0.0.50:22 root@$m1 -fN

# Mark the internal target — use 127.0.0.1:9000 since that's what you'll connect to
mark internal-db 127.0.0.1
# But $m2 is now 127.0.0.1, ambiguous if you have other locals; better:
mark "internal-db (10.0.0.50 via m1) 127.0.0.1"

# Connect
mssh m2 -p 9000        # ssh root@127.0.0.1 -p 9000
```

### Quick chip swap mid-session

You're SSH'd into m1 in pane 2, doing post-exploit. Want to mark a new internal box you discovered:

1. Don't switch panes — hit `prefix + t` from inside the SSH session
2. Tmux prompt appears at the bottom (your remote shell doesn't see it)
3. Type `internal-jumphost 10.0.0.5`, Enter
4. Chip appears, `$m3` becomes available in your local panes (after they hit Enter once)
5. You can keep using the SSH session uninterrupted

---

## 10. Troubleshooting

### `mark` command not found

You sourced the shell file but it didn't take. Try:
```bash
source ~/.zshrc      # or ~/.bashrc
```
Or open a fresh terminal. If still missing, the install snippet wasn't appended — re-run `~/.tmux/plugins/huntermark/install.sh`.

### Chip doesn't appear on the status bar

You haven't wired the widget into your `status-right`. Recommended (instant updates):
```tmux
set -g status-right "#{@huntermark-bar} %H:%M %d-%b "
```
Reload tmux conf (`prefix + r` or your reload binding).

If you're on an older tmux that doesn't support `#{@user-option}` interpolation, fall back to the legacy form (refreshes within `status-interval`, default 5 s):
```tmux
set -g status-right "#(/home/$USER/.config/tmux/plugins/huntermark/scripts/mark-status.sh) %H:%M %d-%b "
```

### `prefix + t` opens "rename window" not the mark prompt

You haven't reloaded tmux conf since installing HunterMark. Reload it. If the conflict persists, your `tmux.conf` has its own `bind t` — explicitly unbind it before the plugin loads:
```tmux
unbind t
```

### `$m1 not set` when running `mssh m1`

The shell hasn't sourced `~/.tmux/marks.sh` yet. Hit Enter once to trigger precmd, then retry. If it still fails, the file might be empty — check with `mark` (no args).

### Chip shows last 3 but I have 5 marks — where are the others?

By design — the bar caps at 3 by default to avoid clutter. The full set is in `mark` (no-args output) and as `$mN` variables. To raise the cap:
```tmux
set -g @huntermark-max-chips 5
```

### `mark undo` says "trash empty" but I just deleted something

`unmark all` clears the LIVE marks but trash still holds them. Check:
```bash
ls ~/.tmux/marks-trash.sh
cat ~/.tmux/marks-trash.sh
```
If empty/missing, the trash was previously cleared (manual rm) or `HUNTERMARK_TRASH_LIMIT` got exceeded.

### Names with special characters look weird in `$mN_full`

Marks are stored via `printf %q`, which escapes spaces, quotes, and shell metacharacters. When zsh sources the file, the value is restored correctly. The escaped form only matters if you read the file directly.

---

## 11. Customization

All optional. Set in your `tmux.conf` before the `run` line that loads TPM:

```tmux
# Chord rebinds
set -g @huntermark-chord-add 't'              # default 't'
set -g @huntermark-chord-remove 'M-t'         # default 'M-t'
set -g @huntermark-chord-help 'M-h'           # default 'M-h'

# Visual
set -g @huntermark-max-chips 3                # how many chips on the status bar
set -g @huntermark-style-index 'fg=brightblack'   # styling of "mN:" prefix
set -g @huntermark-style-value 'fg=yellow,bold'   # styling of the chip value
```

Shell-side env vars (set in `~/.bashrc` / `~/.zshrc` before the `source` line):

```bash
export HUNTERMARK_TRASH_LIMIT=50              # default 20 — how many deletions to keep
export HUNTERMARK_HELPER_DIR=/path/to/helpers # default ~/.config/tmux
export HUNTERMARK_HELP_FILE=/path/to/help.txt # default ~/.config/tmux/huntermark-help.txt
```

---

## 12. What's NOT in HunterMark today

These are deliberate omissions. Reasonable adds in future versions if there's demand:

- **Pin / primary mark** — no way to mark one as the "focal" target with distinct styling
- **Per-mark metadata** — no fields for OS, privilege level, found credentials, notes
- **By-name lookup** — `mark lookup forge` to find the index for a known name
- **Multi-target / engagement scoping** — all marks live in one global namespace
- **OPSEC redact mode** — chip always shows full text on the bar (visible in screenshots)
- **Bulk undo** — `mark undo` restores one at a time, even after `unmark all`
- **Liveness check** — chip doesn't dim when the host becomes unreachable
- **Auto SSH wrapping** — no auto-detection of "you just SSH'd into a box, want to mark it?"

If any of these matter for your workflow, open an issue. Most are clean follow-ons that fit the current file format.
