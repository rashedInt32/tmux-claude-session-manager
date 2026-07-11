#!/usr/bin/env bash
# Answer a Claude permission prompt from the picker, WITHOUT switching to its pane.
#
#   permit.sh <pid> <pane-id> <approve|reject>
#
# An agent blocks on a permission prompt in one of two places, and each takes a
# different delivery:
#   embedded  Claude runs inside a nvim `:terminal` (sidekick.nvim). Its pane is
#             the editor's, so send-keys would land in nvim, not the prompt.
#             sidekick exports NVIM=<servername> into the agent's environment, so
#             that socket is read straight off the agent's env and the keystroke
#             is handed to nvim, which chansends it into the terminal channel.
#   direct    Claude owns the pane itself (a loose pane or a `claude-*` popup
#             session). No NVIM in its env -> type the key in with send-keys.
#
# Fires only while the agent is actually `waiting`: a stray key must never land as
# literal text in a busy or idle agent. `1` is Claude's affirmative menu option;
# Esc cancels.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

pid="${1:?usage: permit.sh <pid> <pane> <approve|reject>}"
pane="${2:?missing pane}"
action="${3:?missing action}"
base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Guard: only answer an agent that is blocked on you. Reading the session file is
# cheaper than asking Claude and gives the live status directly.
status="$(jq -r '.status // empty' "$base/sessions/$pid.json" 2>/dev/null)"
if [ "$status" != waiting ]; then
  tmux display-message "claude: agent $pid is not waiting (status: ${status:-gone})"
  exit 0
fi

# Embedded in nvim? The agent's own environment answers exactly.
nvim_sock="$(agent_nvim_sock "$pid")"

if [ -n "$nvim_sock" ] && [ -S "$nvim_sock" ]; then
  # Hand the key to that nvim; permit() chansends it into the sidekick terminal
  # whose job hosts this agent. No window ever has to gain focus. The function
  # lives in claude-sessions.nvim; the config.claude_sessions fallback keeps a
  # pre-plugin dotfiles setup working.
  nvim --server "$nvim_sock" --remote-expr \
    "luaeval('(function() local ok, m = pcall(require, \"claude-sessions\") if not ok then m = require(\"config.claude_sessions\") end return m.permit(_A[1], _A[2]) end)()', ['$action', $pid])" \
    >/dev/null 2>&1 ||
    tmux display-message "claude: could not reach nvim for agent $pid"
else
  # Direct pane: type the key straight into Claude. -l sends it literally so a
  # digit is never read as a tmux key-table name.
  case "$action" in
  approve) tmux send-keys -t "$pane" -l 1 ;;
  reject) tmux send-keys -t "$pane" Escape ;;
  *)
    tmux display-message "claude: unknown action '$action'"
    exit 0
    ;;
  esac
fi
