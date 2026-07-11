#!/usr/bin/env bash
# Render the picker preview for one agent.
#
#   preview.sh <pid> <pane-id>
#
# A direct-pane agent owns its pane, so a colored capture-pane of that pane is the
# real view. An agent embedded in a nvim `:terminal` (sidekick) does NOT: its pane
# belongs to the editor, so capture-pane shows a code split and, at best, the tail
# of the CLI split — never the conversation. For those, pull the sidekick terminal
# buffer's tail straight from that nvim over its socket (sidekick exports NVIM into
# the agent's env), which is the actual Claude output. That path is plain text; the
# terminal buffer carries no color.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

pid="${1:?usage: preview.sh <pid> <pane>}"
pane="${2:?missing pane}"

nvim_sock="$(agent_nvim_sock "$pid")"

if [ -n "$nvim_sock" ] && [ -S "$nvim_sock" ]; then
  nvim --server "$nvim_sock" --remote-expr \
    "luaeval('require(\"config.claude_sessions\").preview(_A)', $pid)" 2>/dev/null ||
    tmux capture-pane -ept "$pane" # fall back to the pane if the RPC call fails
else
  tmux capture-pane -ept "$pane"
fi
