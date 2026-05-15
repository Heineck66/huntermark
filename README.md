# HunterMark

Target tracker for tmux. Designate machines you're hunting, get them as `$mN` shell variables, see them as chips on your tmux status bar.

Inspired by D&D's Hunter's Mark spell — designate prey, gain tracking advantages.

## What it does

```
                                       status bar
──────────────────────────────────────────────────────────────────────────────────────
 alpha   m1: DC01 10.10.10.40 | m2: Devbox 10.10.10.99 | m3: WS01 10.10.10.55 | (+2)
──────────────────────────────────────────────────────────────────────────────────────
                  ↑                       ↑                       ↑           ↑
            pinned (cyan)            unpinned recency       unpinned recency  hidden
```

```bash
$ mark Forge 10.10.10.42                  # add a mark; $m1=10.10.10.42
$ mark Devbox 10.10.10.99                 # $m2=10.10.10.99
$ mark DC01 10.10.10.40 dc01.lab.local    # AD-style: $m3=10.10.10.40, $m3_host=dc01.lab.local
$ mark
INDEX  NAME    IP             HOST            PIN
m1     Forge   10.10.10.42    -               -
m2     Devbox  10.10.10.99    -               -
m3     DC01    10.10.10.40    dc01.lab.local  -

$ mssh m1                                 # ssh root@10.10.10.42
$ mnmap m2 -sV -p 22,80,443               # nmap -sV -p 22,80,443 10.10.10.99
$ evil-winrm -i $(mhost m3) -u Admin -H … # kerberos-aware tools get the hostname

$ mark edit m1 Forge 10.10.10.43          # in-place fix; index preserved
$ mark pin m3                             # keep m3 sticky on the bar
$ unmark m1                               # soft-deleted to trash; $m1 unset
$ mark undo                               # pop most recent deletion back
$ mark history                            # tail last 20 ops
$ unmark m1,m3                            # remove multiple
$ unmark all                              # confirms first; clears everything
$ mark --help                             # rejected — duplicate detection also catches collisions
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
- `prefix + m` → all-marks popup (browse, pin, unpin)

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

To see chips on your status bar, add the `@huntermark-bar` user option to your `status-right` (or `status-left`):

```tmux
set -g status-right "#{@huntermark-bar} %H:%M %d-%b "
```

Reload tmux conf. Chips appear when you add marks, and disappear instantly when you remove them — mutations push directly to the option, so there's no `status-interval` polling lag.

<details>
<summary>Legacy <code>#(...)</code> form</summary>

If you're on an older tmux that doesn't support `#{@user-option}` interpolation, the script is still callable directly. Chip changes will reflect within `status-interval` (default 5 s):

```tmux
set -g status-right "#(/home/$USER/.config/tmux/plugins/huntermark/scripts/mark-status.sh) %H:%M %d-%b "
```
</details>

## Configuration

All optional; defaults shown in parens.

```tmux
set -g @huntermark-chord-add 't'                    # (default 't')
set -g @huntermark-chord-remove 'M-t'               # (default 'M-t')
set -g @huntermark-chord-help 'M-h'                 # (default 'M-h')
set -g @huntermark-chord-popup 'm'                  # (default 'm') — all-marks popup
set -g @huntermark-max-chips 3                      # how many chips to show
set -g @huntermark-style-index 'fg=brightblack'     # styling of "mN:" prefix
set -g @huntermark-style-value 'fg=yellow,bold'     # styling of the chip value
set -g @huntermark-style-pin 'fg=cyan,bold'         # styling of pinned-mark index
set -g @huntermark-style-overflow 'fg=brightblack'  # styling of "(+X)" overflow chip
```

## How it works

- **Storage**: `~/.tmux/marks.sh` is one file with `export mN=<value>` and `export mN_full=<input>` lines per mark, plus optional `export mN_host=<fqdn>` (for AD/Kerberos) and `export mN_pinned=1` (for sticky bar slots). Sourced on every shell prompt.
- **Cross-pane visibility**: a `precmd` (zsh) or `PROMPT_COMMAND` (bash) hook sources `~/.tmux/marks.sh` on every prompt. New marks appear as `$mN` in all open shells after they next render a prompt.
- **Chip rendering (push model)**: every mutation script (`mark-set`, `mark-remove`, `mark-edit`, `mark-undo`, `mark-pin`) calls `scripts/mark-status.sh` at the end. The render rule is `pinned (ascending) ++ unpinned (newest first)`, capped at `@huntermark-max-chips`; if any marks are dropped, a dim `(+X)` overflow chip is appended. The result is written to the `@huntermark-bar` tmux user option, and `refresh-client -S` triggers an immediate redraw — so all mutations reflect on the bar instantly.
- **Removal preserves indices**: removing m2 doesn't renumber m3 → m2. Stable references matter when you've memorized "$m4 is the kerberoastable one."
- **Input parsing**: first IPv4 in the input wins `$mN`. If the input also has a multi-label hostname (e.g. `dc01.lab.local`), it's stored as `$mN_host`. With no IPv4, a multi-label hostname becomes the primary; with neither, a single-label NetBIOS-style hostname is accepted (for AD labs). Inputs matching none of the above are rejected.
- **Duplicate detection**: `mark` rejects any new input whose IP or hostname collides with an existing mark's `$mN` or `$mN_host` (hostnames compared case-insensitively).
- **AD/Kerberos support**: `mhost mN` resolves to the hostname (`$mN_host` if set, else `$mN`) and fails loudly when the resolved value is an IPv4 — the typical input for `kinit`, `evil-winrm`, `impacket-secretsdump -k`.

## Documentation

- **[docs/usage.md](docs/usage.md)** — full walk-through guide: workflows, examples, troubleshooting, customization
- **[docs/help.txt](docs/help.txt)** — terse one-screen cheatsheet (also opens via `prefix + Alt + h`)
- **[docs/architecture.md](docs/architecture.md)** — moving-parts diagram + data flows

## Credits

Built on top of `tmux`, `bash`, and `zsh`. Hunter's Mark is a Ranger spell from Dungeons & Dragons 5th Edition.

## License

MIT.
