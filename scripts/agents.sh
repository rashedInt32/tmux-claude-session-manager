#!/usr/bin/env bash
# Emit one picker row per running Claude that lives in a tmux pane.
#
# Reads ~/.claude/sessions/<pid>.json directly rather than shelling out to
# `claude agents --json`, which costs ~210ms of Node startup. Falls back to the
# CLI when those files are absent. `statusUpdatedAt` gives last-activity
# directly, so no transcript glob is needed.
#
# A session file outlives an agent killed with SIGKILL, so a recycled PID could
# surface a bogus row that ctrl-x would then kill. `comm` is checked to rule
# that out. Note lstart/procStart cannot be compared: ps reports local time,
# Claude writes UTC.
#
#   Row: rank \t pane_id \t pid \t kind \t icon \t age \t loc \t path
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# pid \t status \t sessionId \t cwd \t statusUpdatedAt(ms)
rows="$(jq -r -s '
  .[] | select(.kind == "interactive")
      | [.pid, .status, .sessionId, .cwd, (.statusUpdatedAt // .updatedAt // 0)]
      | @tsv' "$base"/sessions/*.json 2>/dev/null)"

# Fallback: no session files (older Claude Code, or the layout moved).
if [ -z "$rows" ]; then
  rows="$(claude agents --json 2>/dev/null |
    jq -r '.[] | select(.kind == "interactive") | [.pid, .status, .sessionId, .cwd, 0] | @tsv' 2>/dev/null)"
fi
[ -n "$rows" ] || exit 0

{
  ps -Ao pid=,tty=,comm= 2>/dev/null | awk '{ print "P\t" $1 "\t" $2 "\t" $3 }'
  tmux list-panes -a -F $'T\t#{pane_tty}\t#{pane_id}\t#{session_name}\t#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null
  printf '%s\n' "$rows" | sed $'s/^/A\t/'
} | awk -F'\t' -v now="$(date +%s)" -v home="$HOME" \
  -v prefix="$(get_tmux_option @claude_session_prefix 'claude-')" '
  $1 == "P" { tty_of[$2] = $3; comm_of[$2] = $4; next }
  $1 == "T" { sub(/^\/dev\//, "", $2); pane[$2] = $3; sess[$2] = $4; loc[$2] = $5; next }
  $1 == "A" {
    pid = $2; status = $3; cwd = $5; upd = $6

    tty = tty_of[pid]
    if (tty == "" || !(tty in pane)) next          # not running inside tmux

    # Stale file + recycled PID. Fail open: only drop when we can positively
    # identify the live process as something other than a Claude.
    c = comm_of[pid]
    if (c != "" && c !~ /claude|node/) next

    if      (status == "waiting") { icon = "\033[33m●\033[0m waiting"; rank = 0 }
    else if (status == "idle")    { icon = "\033[32m●\033[0m idle   "; rank = 1 }
    else if (status == "busy")    { icon = "\033[31m●\033[0m working"; rank = 3 }
    else                          { icon = "\033[90m●\033[0m   ?    "; rank = 2 }

    age = (upd > 0) ? int((now - upd / 1000) / 60) "m" : "-"
    kind = (index(sess[tty], prefix) == 1) ? "dedicated" : "loose"

    path = cwd
    if (index(path, home) == 1) path = "~" substr(path, length(home) + 1)

    printf "%s\t%s\t%s\t%s\t%s\t%5s\t%s\t%s\n",
      rank, pane[tty], pid, kind, icon, age, loc[tty], path
  }
' | sort -t$'\t' -k1,1n -k6,6n
