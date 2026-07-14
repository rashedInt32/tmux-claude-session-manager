#!/usr/bin/env bash
# Open the session picker in a popup.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

# The client that pressed the key, and the session it is currently attached to.
# Looked up by exact client_name match rather than "first client anywhere that
# looks nested" — with more than one client attached (e.g. a stray popup left
# open in another window), a global scan can grab an unrelated client's session
# and detach it instead of the one this invocation actually cares about.
me="${1:-}"
my_session="$(tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
  awk -v me="$me" '$1 == me { print $2; exit }')"

# Popup sessions are recognised by the @claude_popup marker launch.sh sets at
# creation, NOT by the session-name prefix: a user session whose name merely
# starts with the prefix (e.g. project dir claude-foo) must not be detached —
# that would close the user's terminal, not a popup.
if [ -n "$my_session" ] &&
  [ "$(tmux show-options -qv -t "$my_session:" @claude_popup 2>/dev/null)" = 1 ]; then
  # We are inside a session popup: close it, then reopen the picker on the
  # outer client that originally opened it.
  tmux detach-client -s "$my_session"
  for _ in $(seq 1 100); do
    tmux list-clients -F '#{session_name}' 2>/dev/null | grep -qx "$my_session" || break
    sleep 0.05
  done
  host="$(tmux show-options -gqv @claude_parent 2>/dev/null)"
else
  # Normal case: this client is already the host.
  host="$me"
  tmux set-option -g @claude_parent "$host"
fi

# Host the picker on the outer client. -c is honored because that client has no
# popup open now; fall back to the default client if none was found.
if [ -n "$host" ]; then
  tmux display-popup -c "$host" -w "$w" -h "$h" -E "$DIR/picker.sh"
else
  tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
fi
