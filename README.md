# HunterMark

Target tracker for tmux. Designate machines you're hunting, get them as `$mN` shell variables, see them as chips on your tmux status bar.

Inspired by D&D's Hunter's Mark spell — designate prey, gain tracking advantages.

## What it does

```
                                  status bar
─────────────────────────────────────────────────────────────────────────────
 alpha   m1: Forge 10.10.10.42 | m2: Devbox 10.10.10.99 | m3: Box3 10.10.10.55
─────────────────────────────────────────────────────────────────────────────
                          ↑                   ↑                   ↑
                   shows up to 3 most recent marks; older still in $mN
```

```bash
$ mark Forge 10.10.10.42         # add a mark; $m1=10.10.10.42; chip appears
$ mark Devbox 10.10.10.99        # $m2=10.10.10.99
$ mark Box3 10.10.10.55          # $m3
$ mark
INDEX  NAME    IP
m1     Forge   10.10.10.42
m2     Devbox  10.10.10.99
m3     Box3    10.10.10.55

$ mssh m1                        # ssh root@10.10.10.42
$ mnmap m2 -sV -p 22,80,443      # nmap -sV -p 22,80,443 10.10.10.99
$ mcurl m3 -sI                   # curl -sI http://10.10.10.55

$ mark edit m1 Forge 10.10.10.43 # in-place fix; $m1 stays m1, value updated
$ unmark m1                      # soft-deleted to trash; $m1 unset; chip drops off
$ mark undo                      # pop most recent deletion back
$ mark history                   # tail last 20 ops (add/edit/remove/undo)
$ unmark m1,m3                   # remove multiple
$ unmark all                     # confirms first; clears everything
```

## Why

If you do CTF / HTB / pentest engagements you juggle multiple target machines. You end up scribbling IPs in notes, copy-pasting into commands, forgetting which is which. HunterMark gives you stable shell variables (`$m1`, `$m2`) that survive across panes via a `precmd` source hook, plus an at-a-glance chip on the tmux status bar.

## Requirements

- tmux 3.2+ (for `display-popup`)
- bash or zsh
- Standard utilities: `grep`, `sed`, `awk`, `column`, `sort`, `printf` (BusyBox or GNU both fine)
- `find` if you also want fzf-friendly fuzzy lookup (optional)

## Install

### 1. Tmux side (via TPM)

Add to your `tmux.conf`:

```tmux
set -g @plugin '<your-fork>/huntermark'
```

Then `prefix + I` to install. This registers:

- `prefix + t` → add a mark
- `prefix + M-t` → remove marks
- `prefix + M-h` → cheatsheet popup

### 2. Shell side

Run the installer once:

```bash
~/.tmux/plugins/huntermark/install.sh
```

This:
- Detects your shell (bash or zsh)
- Appends a small snippet to `~/.bashrc` or `~/.zshrc` that sources `huntermark.{bash,zsh}`
- Copies the cheatsheet to `~/.config/tmux/huntermark-help.txt` so the popup binding works

Open a new shell (or `source ~/.bashrc` / `source ~/.zshrc`) to pick up the functions.

### 3. Status bar widget (optional but recommended)

To see chips on your status bar, add the widget path to your `status-right` (or `status-left`):

```tmux
set -g status-right "#(/home/$USER/.config/tmux/plugins/huntermark/scripts/mark-status.sh) %H:%M %d-%b "
```

Reload tmux conf. Chips appear when you add marks.

## Configuration

All optional; defaults shown in parens.

```tmux
set -g @huntermark-chord-add 't'              # (default 't')
set -g @huntermark-chord-remove 'M-t'         # (default 'M-t')
set -g @huntermark-chord-help 'M-h'           # (default 'M-h')
set -g @huntermark-max-chips 3                # how many chips to show
set -g @huntermark-style-index 'fg=brightblack'   # style of "mN:" prefix
set -g @huntermark-style-value 'fg=yellow,bold'   # style of the chip value
```

## How it works

- **Storage**: `~/.tmux/marks.sh` holds `export mN=<ip>` and `export mN_full=<input>` lines, one set per mark. Idempotent appends.
- **Cross-pane visibility**: a `precmd` (zsh) or `PROMPT_COMMAND` (bash) hook sources `~/.tmux/marks.sh` on every prompt. New marks appear as `$mN` in all open shells after they next render a prompt.
- **Chip rendering**: `scripts/mark-status.sh` reads `~/.tmux/marks.sh`, sorts by N, takes the most recent 3 (or `@huntermark-max-chips`), emits styled tmux format strings. Tmux re-renders the bar every `status-interval`.
- **Removal preserves indices**: removing m2 doesn't renumber m3 → m2. Stable references matter when you've memorized "$m4 is the kerberoastable one."
- **IP parsing**: first IPv4 in the input becomes `$mN`. If no IPv4 found, the full input becomes `$mN`.

## Documentation

- **[docs/usage.md](docs/usage.md)** — full walk-through guide: workflows, examples, troubleshooting, customization
- **[docs/help.txt](docs/help.txt)** — terse one-screen cheatsheet (also opens via `prefix + M-h`)
- **[docs/architecture.md](docs/architecture.md)** — moving-parts diagram + data flows

## Credits

Built on top of `tmux`, `bash`, and `zsh`. Hunter's Mark is a Ranger spell from Dungeons & Dragons 5th Edition.

## License

MIT.
