#!/usr/bin/env bash
# Interactive picker for running Claude agents.
#
#   picker.sh           fzf picker; on enter, jumps to the chosen agent.
#   picker.sh --list    print the rows only (used by fzf's ctrl-x reload).
#
# Rows come from agents.sh, which pairs each running Claude with the tmux pane it
# occupies. Two kinds of row jump differently:
#   dedicated  a Claude in a `claude-*` session this plugin launched — resumed in
#              the popup, over the window it was launched from.
#   loose      a Claude running in any other pane — focused in place.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

[ "${1:-}" = '--list' ] && exec "$DIR/agents.sh"

for tool in fzf jq claude; do
  command -v "$tool" >/dev/null 2>&1 || {
    tmux display-message "tmux-claude-session-manager: $tool is required for the picker"
    exit 0
  }
done

self="$DIR/picker.sh"
export FZF_DEFAULT_OPTS=''
export CLAUDE_PICKER="$self"

# Arbitrary user fzf options (e.g. custom --bind or --preview-window)
extra_opts=()
fzf_options="$(get_tmux_option @claude_fzf_options '')"
[ -n "$fzf_options" ] && eval "extra_opts=($fzf_options)"

# Auto-refresh the preview so a running agent's output streams in on its own,
# rather than freezing at the snapshot taken when you highlighted it. fzf has no
# periodic timer, so drive it from outside: --listen opens a control port, the
# start bind writes it out, and a background loop POSTs refresh-preview once a
# second until fzf exits. Degrades to the manual ctrl-l re-poll when curl is
# absent. refresh_pid/portfile are cleaned up on exit.
refresh_pid=""
portfile=""
cleanup() {
  [ -n "$refresh_pid" ] && kill "$refresh_pid" 2>/dev/null
  [ -n "$portfile" ] && rm -f "$portfile"
}
trap cleanup EXIT

live_opts=()
if command -v curl >/dev/null 2>&1; then
  portfile="$(mktemp)"
  live_opts=(--listen --bind "start:execute-silent:echo \$FZF_PORT > $portfile")
  (
    # Wait for the port, then poke fzf every second. The loop ends when the port
    # file is removed on exit; the iteration cap is just a runaway backstop.
    for _ in $(seq 1 36000); do
      [ -f "$portfile" ] || break
      port="$(cat "$portfile" 2>/dev/null)"
      [ -n "$port" ] && curl -s -XPOST "localhost:$port" -d 'refresh-preview' >/dev/null 2>&1
      sleep 1
    done
  ) &
  refresh_pid=$!
fi

# ctrl-x kills the Claude process itself: a dedicated session dies with its last
# window, while a loose pane keeps the shell that hosted it. The reload waits a
# beat so the supervisor has dropped the agent from `claude agents --json`.
#
# ctrl-y / ctrl-r answer a permission prompt in place: permit.sh delivers the key
# to the highlighted agent (nvim-embedded or a bare pane alike) without switching
# to it, then refresh-preview re-captures the pane so you watch it get answered.
# The short sleep lets Claude's TUI redraw before the snapshot. ctrl-l forces a
# manual re-poll (redundant with the auto-refresh, but handy when it's disabled).
sel=$("$DIR/agents.sh" | fzf --ansi --delimiter='\t' --with-nth=5,6,7,8 \
  --reverse --cycle \
  --header='enter: jump · ctrl-y: approve · ctrl-r: reject · ctrl-l: refresh · ctrl-x: kill' \
  --preview="$DIR/preview.sh {3} {2}" --preview-window='up,70%,follow' \
  --bind="ctrl-x:execute-silent(kill {3})+reload(sleep 0.3; $self --list)" \
  --bind="ctrl-y:execute-silent($DIR/permit.sh {3} {2} approve; sleep 0.3)+refresh-preview" \
  --bind="ctrl-r:execute-silent($DIR/permit.sh {3} {2} reject; sleep 0.3)+refresh-preview" \
  --bind='ctrl-l:refresh-preview' \
  ${live_opts[@]+"${live_opts[@]}"} \
  ${extra_opts[@]+"${extra_opts[@]}"})

[ -z "$sel" ] && exit 0
pane=$(printf '%s' "$sel" | cut -f2)
kind=$(printf '%s' "$sel" | cut -f4)

parent=$(tmux show-options -gqv @claude_parent 2>/dev/null)
session=$(tmux display-message -p -t "$pane" '#{session_name}' 2>/dev/null)

if [ "$kind" = loose ]; then
  # Focus the pane in place on the outer client. This popup closes on its own
  # when the script exits.
  if [ -n "$parent" ]; then
    tmux switch-client -c "$parent" -t "$session" 2>/dev/null
  else
    tmux switch-client -t "$session" 2>/dev/null
  fi
  tmux select-window -t "$pane" 2>/dev/null
  tmux select-pane -t "$pane" 2>/dev/null
  exit 0
fi

# Move the parent client to the window the session was launched from (best-effort),
# focus the chosen Claude's own window inside that session, then resume it in THIS
# popup over the top. Falls back to resuming over the current window when
# origin/parent are unknown.
origin=$(tmux show-options -qv -t "$session" @claude_origin 2>/dev/null)
[ -n "$origin" ] && [ -n "$parent" ] &&
  tmux switch-client -c "$parent" -t "$origin" 2>/dev/null

tmux select-window -t "$pane" 2>/dev/null
tmux select-pane -t "$pane" 2>/dev/null
tmux attach-session -t "$session"
