# tmux-claude-session-manager

> ## 🍴 About this fork
>
> This is a fork of [craftzdog/tmux-claude-session-manager](https://github.com/craftzdog/tmux-claude-session-manager).
> The original picker is a jump-to-session list. This fork turns it into a
> **remote control for every Claude agent on your machine**, including agents
> running inside nvim. What it adds:
>
> - ⚡ **A ~10× faster picker.** Agent state comes from `~/.claude/sessions/*.json`
>   and each agent's own environment, instead of shelling out to `claude agents --json`:
>
>   | source of truth                           | picker opens in |
>   | ----------------------------------------- | --------------- |
>   | `claude agents --json` + `ps -A` (upstream) | `0.25s`       |
>   | session files + `TMUX_PANE` (this fork)     | `0.02s`       |
>
> - ✅ **Answer permission prompts from the picker.** Press `ctrl-y` to approve
>   or `ctrl-r` to reject the highlighted agent, then watch it proceed in the
>   preview. You never leave your pane.
> - 🖥️ **Agents inside nvim are first-class.** A Claude running in `:terminal` or
>   [sidekick.nvim](https://github.com/folke/sidekick.nvim) is found, previewed,
>   approved and rejected like any other agent. The preview shows the actual
>   conversation, pulled over the editor's RPC socket, not a screenshot of the
>   editor.
> - 📺 **Live preview.** The preview refreshes every second while the picker is
>   open (`fzf --listen`), so you can watch a working agent stream its output.
>   `ctrl-l` re-polls manually.
> - 🛡️ **Recycled-PID guard.** A stale session file can't show (or `ctrl-x` kill)
>   an unrelated process. A row only appears when the live process is really a
>   Claude.
>
> Approve/reject and conversation preview for nvim-embedded agents need the
> companion nvim plugin, [claude-sessions.nvim](https://github.com/rashedInt32/claude-sessions.nvim),
> which also puts every agent's status in your statusline. Everything else works
> with tmux + fzf + jq alone.

[![screenshot](./docs/screenshot.jpg)](https://youtu.be/NnTV6r4l5D0)

Run many [Claude Code](https://claude.com/claude-code) sessions across your
projects, each in its own tmux session. Then **list them, see which are done
and which are still working, and jump to one**, all from a single popup.

If you launch Claude per directory (one nested session per project), you
quickly end up with a dozen of them and no way to tell which are finished
without opening each one. This plugin gives you:

- 🔢 **A central picker** (`prefix` + `u`) that lists every running Claude
  agent: several in one project, one running loose in an ordinary pane, or one
  inside an embedded terminal such as nvim's `:terminal` or `sidekick.nvim`.
- 🟢 **Live status** per agent (`working` / `waiting` / `idle`), read straight
  from the state each agent publishes. You instantly see which ones need you.
- 👁️ **A live preview** of each agent's screen right in the picker.
- 🎯 **Smart jump.** Selecting an agent switches to the window it was launched
  from, then resumes it in a popup over it.
- 🚀 **A launcher** (`prefix` + `y`) that opens or re-attaches a Claude session
  for the current directory.
- ❌ **Quick kill** (`ctrl-x`) for a finished agent, right from the picker.

Status needs no configuration. Claude Code publishes each agent's state and the
picker reads it. There are no hooks to install.

## Prerequisites

- **tmux ≥ 3.2** (for `display-popup`)
- **[fzf](https://github.com/junegunn/fzf)**: the picker UI
- **[jq](https://jqlang.org/)**: parses the agent state
- **[Claude Code](https://claude.com/claude-code)** ≥ 2.1.139: for the
  `claude agents` command, used as a fallback (`claude --version` to check)
- **curl**: optional, drives the preview auto-refresh (without it, `ctrl-l`
  re-polls manually)
- bash; macOS or Linux

## Install (tpm)

Add to `~/.tmux.conf` (or `~/.config/tmux/tmux.conf`):

```tmux
set -g @plugin 'rashedInt32/tmux-claude-session-manager'
```

(Use `craftzdog/tmux-claude-session-manager` for the original without the fork
additions above.)

Then hit `prefix` + <kbd>I</kbd> to install.

> **Keybinding note:** by default the plugin binds `prefix` + `y` (launch) and
> `prefix` + `u` (list). If your config binds those elsewhere, either change the
> options below, or make sure the plugin loads **after** your own bindings (put
> `run '~/.tmux/plugins/tpm/tpm'` _after_ them) so the one you want wins.

### Manual install

```sh
git clone https://github.com/rashedInt32/tmux-claude-session-manager ~/clone/path
```

Add to `~/.tmux.conf`, then reload (`prefix` + <kbd>r</kbd> or `tmux source ~/.tmux.conf`):

```tmux
run-shell ~/clone/path/claude_session_manager.tmux
```

## Usage

| Key            | Action                                                                          |
| -------------- | ------------------------------------------------------------------------------- |
| `prefix` + `y` | Launch (or re-attach to) a Claude session for the current directory, in a popup |
| `prefix` + `u` | Open the agent picker                                                           |

Inside the picker:

| Key                       | Action                                                        |
| ------------------------- | ------------------------------------------------------------- |
| `enter`                   | Jump to the agent (see [How it works](#how-it-works))         |
| `ctrl-y`                  | **Approve** the agent's permission prompt, without jumping    |
| `ctrl-r`                  | **Reject** the agent's permission prompt, without jumping     |
| `ctrl-l`                  | Re-poll the preview (it also auto-refreshes once a second)    |
| `ctrl-x`                  | Kill the highlighted agent                                    |
| `↑` / `↓`, type to filter | fzf navigation                                                |

`ctrl-y` and `ctrl-r` only fire while the agent is actually `waiting`, so a
stray key can never land as literal text in a busy or idle agent. For an agent
in a bare pane, the key is typed straight into it (`send-keys`). For one
embedded in nvim, it is routed through the editor's RPC socket into the exact
terminal hosting that agent.

Agents that need your attention (`waiting`, `idle`) sort to the top.

Every running Claude gets its own row. The picker identifies each agent by its
process, not by its tmux session. So several agents in one project all show up
separately, and so does a Claude you started by hand in an ordinary pane.

## Options

Set any of these before the plugin loads (defaults shown):

```tmux
set -g @claude_launch_key     'y'        # prefix key: launch/open for current dir
set -g @claude_list_key       'u'        # prefix key: open the picker
set -g @claude_command        'claude'   # command run in new sessions
set -g @claude_args           ''         # extra args appended to the command
set -g @claude_session_prefix 'claude-'  # tmux session name prefix
set -g @claude_popup_width     '90%'     # popup width
set -g @claude_popup_height    '90%'     # popup height
set -g @claude_fzf_options    ''         # extra options passed to the fzf picker
```

For example, to skip permission prompts in launched sessions:

```tmux
set -g @claude_args '--dangerously-skip-permissions'
```

### Customizing the fzf picker

`@claude_fzf_options` is passed straight to `fzf`, so you can add your own bindings.

Here is a vim keybinding example:

```tmux
set -g @claude_fzf_options "\
  --prompt 'nav> ' \
  --bind 'j:down' \
  --bind 'k:up' \
  --bind 'q:abort' \
  --bind 'x:execute-silent(kill {3})+reload(sleep 0.3; \$CLAUDE_PICKER --list)' \
  --bind 'i:unbind(j,k,q,i,a,x)+change-prompt(filter> )' \
  --bind 'a:unbind(j,k,q,i,a,x)+change-prompt(filter> )' \
  --bind 'esc:rebind(j,k,q,i,a,x)+change-prompt(nav> )'"
```

The picker opens in **nav** mode:

| Key       | Action                                                  |
| --------- | ------------------------------------------------------- |
| `j` / `k` | move down / up                                          |
| `i` / `a` | switch to **filter** mode (type to fuzzy-match)         |
| `x`       | kill the highlighted agent (like the built-in `ctrl-x`) |
| `q`       | close the picker                                        |
| `enter`   | jump to the agent (both modes)                          |
| `esc`     | filter mode → back to nav                               |

Only the bound keys are special in nav mode; any other key still filters as you
type. `x` reloads the list through `$CLAUDE_PICKER`, a path the picker exports
for exactly this. Write it as `\$CLAUDE_PICKER` inside the double-quoted value
above so tmux stores a literal `$` (in a single-quoted value, use a bare
`$CLAUDE_PICKER`).

## How it works

**The launcher** creates a detached `claude-<hash-of-dir>` tmux session running
`claude`, records the window you launched it from in `@claude_origin`, and
attaches to it in a popup.

**The session files are the source of truth.** Every Claude agent self-reports
its state (`busy` / `waiting` / `idle`), and Claude Code writes one file per
agent to `~/.claude/sessions/<pid>.json`. Reading those files is effectively
free. `claude agents --json` publishes the same data, but pays ~200ms of Node
startup on every render, so the CLI is kept only as a fallback for when the
directory is absent. The plugin also never scans processes for a `claude`
command name: on macOS a pane reports its parent shell, never the `claude`
child running inside it.

**Pairing each agent with its pane.** `agents.sh` reads `TMUX_PANE` out of the
agent's own environment. tmux exports it into every pane, and every child
inherits it: through the shell, through an editor, into Claude. That is why an
agent's identity is its process rather than its tmux session, and why several
agents in one project each get their own row. It is also why a Claude inside an
embedded terminal needs no special handling: it simply reports the pane of the
editor hosting it. Nothing walks the process tree, and nothing keys off `tty`.
The OS recycles ttys, but tmux never reuses a `%N` pane id within a server.
`TMUX` also carries the server pid, so agents that belong to another tmux
server are skipped instead of being mis-joined onto a same-numbered pane here.

**The age column** shows `statusUpdatedAt`: the last time the agent changed
state.

**The recycled-PID guard.** An agent killed with `SIGKILL` leaves its session
file behind, and the OS may hand its PID to some unrelated process. Without a
check, that file would surface the wrong process, and `ctrl-x` would signal it.
So a row is dropped unless the live process's **command line** names a Claude.
The whole command line is matched, not just `argv[0]`, so an install that runs
`node .../cli.js` still works without waving through a bare `node`. Two
platform notes: `procStart` can't be compared against `ps`'s `lstart` (the
former is UTC, the latter local time), and macOS won't reveal the environment
of SIP-protected system binaries, so such a process is dropped one step
earlier, at the pane lookup.

**The picker** renders those rows with a live `capture-pane` preview. On
`enter`, a **dedicated** agent (one in a `claude-*` session) resumes in a popup
over the window it was launched from, while a **loose** one (any other pane) is
focused in place. `ctrl-x` kills the Claude process itself: a dedicated session
dies with its last window, and a loose pane keeps the shell that hosted it. For
an agent inside an embedded terminal, `enter` jumps to the pane running the
editor (tmux can't focus a buffer inside it), and `ctrl-x` kills the agent
while leaving the editor running.

**No popup-in-popup.** Pressing `prefix` + `u` from inside a session popup
detaches that popup first (closing it), then reopens the picker full-size on
the outer client. You never end up with a cramped popup inside a popup.

## Performance notes

The timings in [About this fork](#-about-this-fork) measure the delay between
pressing `prefix` + `u` and seeing the list: warm medians over six runs, on
macOS with three agents running. Almost all of the difference is Node startup.
`claude agents --json` spends about 0.20s booting to answer one query, and a
cold run has been seen upwards of `0.9s`. Scoping `ps` to the agent pids,
instead of enumerating every process on the system, accounts for most of the
rest. `ps` scales with the number of processes on the box and `jq` with the
number of agents, so your numbers will differ. The `capture-pane` preview is
not part of this; it renders in under a millisecond.

## License

[MIT](LICENSE) © Takuya Matsuyama
