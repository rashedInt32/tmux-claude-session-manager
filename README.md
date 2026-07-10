# tmux-claude-session-manager

[![screenshot](./docs/screenshot.jpg)](https://youtu.be/NnTV6r4l5D0)

Run many [Claude Code](https://claude.com/claude-code) sessions across your
projects, each in its own tmux session — then **list them, see which are done
vs. still working, and jump to one** from a single popup.

If you launch Claude per-directory (one nested session per project), you quickly
end up with a dozen of them and no way to tell which are finished without opening
each one. This plugin gives you:

- 🔢 **A central picker** (`prefix` + `u`) listing every running Claude agent —
  several in one project, any running loose in an ordinary pane, and any running
  inside an embedded terminal such as nvim's `:terminal` or `sidekick.nvim`.
- 🟢 **Live status** per agent — `working` / `waiting` / `idle` — read straight
  from the state each agent publishes, so you instantly see which need you. No setup.
- 👁️ **A live preview** of each agent's screen right in the picker.
- 🎯 **Smart jump** — selecting an agent switches your client to the window it
  was launched from, then resumes it in a popup over it.
- 🚀 **A launcher** (`prefix` + `y`) that opens/attaches a Claude session for the
  current directory.
- ❌ **Quick kill** (`ctrl-x`) of a finished agent from the picker.

Status needs no configuration. Claude Code publishes each agent's own state and
the picker reads it — there are no hooks to install.

## Prerequisites

- **tmux ≥ 3.2** (for `display-popup`)
- **[fzf](https://github.com/junegunn/fzf)** — the picker UI
- **[jq](https://jqlang.org/)** — parses the agent state
- **[Claude Code](https://claude.com/claude-code)** ≥ 2.1.139 — for the
  `claude agents` command, used as a fallback (`claude --version` to check)
- bash; macOS or Linux

## Install (tpm)

Add to `~/.tmux.conf` (or `~/.config/tmux/tmux.conf`):

```tmux
set -g @plugin 'craftzdog/tmux-claude-session-manager'
```

Then hit `prefix` + <kbd>I</kbd> to install.

> **Keybinding note:** by default the plugin binds `prefix` + `y` (launch) and
> `prefix` + `u` (list). If your config binds those elsewhere, either change the
> options below, or make sure the plugin loads **after** your own bindings (put
> `run '~/.tmux/plugins/tpm/tpm'` _after_ them) so the one you want wins.

### Manual install

```sh
git clone https://github.com/craftzdog/tmux-claude-session-manager ~/clone/path
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

| Key                       | Action                                                |
| ------------------------- | ----------------------------------------------------- |
| `enter`                   | Jump to the agent (see [How it works](#how-it-works)) |
| `ctrl-x`                  | Kill the highlighted agent                            |
| `↑` / `↓`, type to filter | fzf navigation                                        |

Agents needing your attention (`waiting`, `idle`) sort to the top.

Every running Claude gets its own row — the picker identifies each by its process,
not by its tmux session. So several agents in one project all show up separately,
as does a Claude you started by hand in an ordinary pane.

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
| `i` / `a` | switch to **filter** mode — type to fuzzy-match         |
| `x`       | kill the highlighted agent (like the built-in `ctrl-x`) |
| `q`       | close the picker                                        |
| `enter`   | jump to the agent (both modes)                          |
| `esc`     | filter mode → back to nav                               |

Only the bound keys are special in nav mode; any other key still filters as you
type. `x` reloads the list through `$CLAUDE_PICKER`, a path the picker exports for
exactly this — write it as `\$CLAUDE_PICKER` inside the double-quoted value above
so tmux stores a literal `$` (in a single-quoted value, use a bare
`$CLAUDE_PICKER`).

## How it works

- The **launcher** creates a detached `claude-<hash-of-dir>` tmux session running
  `claude`, records the window it came from in `@claude_origin`, and attaches to
  it in a popup.
- **`~/.claude/sessions/<pid>.json`** is the source of truth for what is running
  and how it is doing. Each Claude session self-reports its state (`busy` /
  `waiting` / `idle`) to a supervisor daemon, which writes one file per agent.
  Reading those files is effectively free, whereas `claude agents --json`
  publishes the same data at the cost of ~200ms of Node startup on every render —
  so the CLI is kept only as a fallback for when the directory is absent. Nothing
  here scans processes for a `claude` command name — on macOS a pane reports its
  parent shell, never the `claude` child running inside it.
- **`agents.sh`** pairs each running Claude with its tmux pane by reading
  `TMUX_PANE` out of the agent's own environment. tmux exports it into every
  pane and every child inherits it — through the shell, through an editor, into
  Claude. That is why identity is the Claude _process_ rather than the tmux
  session, and therefore why several agents in one project each get their own
  row. It is also why a Claude inside an embedded terminal needs no special
  handling: it reports the pane of the editor hosting it. Nothing walks the
  process tree, and nothing keys off `tty` — the OS recycles a tty, whereas
  tmux never reuses a `%N` pane id within a server. `TMUX` carries the server
  pid too, so agents belonging to another tmux server are skipped rather than
  mis-joined onto a same-numbered pane here.
- The **age column** is `statusUpdatedAt` — when the agent last changed state.
  A session file left behind by an agent killed with `SIGKILL` could otherwise
  surface a recycled PID, so a row is dropped when the live process's executable
  is not a Claude. Note `procStart` cannot be compared against `ps`'s `lstart`:
  the former is UTC, the latter local time.
- The **picker** renders those rows with a live `capture-pane` preview. On `enter`
  a **dedicated** agent (in a `claude-*` session) resumes in the popup over the
  window it was launched from, while a **loose** one (any other pane) is focused in
  place. `ctrl-x` kills the Claude process itself: a dedicated session dies with
  its last window, and a loose pane keeps the shell that hosted it. An agent inside
  an embedded terminal jumps to the pane running the editor — tmux cannot focus a
  buffer within it — and `ctrl-x` kills the agent while leaving the editor running.
- Pressing `prefix` + `u` **from inside a session popup** detaches that popup
  first (closing it), then reopens the picker full-size on the outer host client —
  so you never end up with a cramped popup-in-popup.

## Performance

Time to build the picker's rows, which is the delay between pressing
`prefix` + `u` and seeing the list:

| source of truth                              | time    |
| -------------------------------------------- | ------- |
| `claude agents --json` + `ps -A`             | `0.25s` |
| `~/.claude/sessions/*.json` + `TMUX_PANE`    | `0.02s` |

Almost all of the difference is Node startup: `claude agents --json` spends
~0.20s booting to answer one query. Scoping `ps` to the agent pids, rather than
enumerating every process on the system, accounts for most of the rest.

Warm medians over six runs, on macOS with three agents running. A cold
`claude agents --json` has been seen to take upwards of `0.9s`. `ps` scales with
the number of processes on the box and `jq` with the number of agents, so your
numbers will differ. The `capture-pane` preview is not part of this — it renders
in under a millisecond, and redrawing it as you move the cursor is free.

## License

[MIT](LICENSE) © Takuya Matsuyama
