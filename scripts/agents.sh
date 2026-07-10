#!/usr/bin/env bash
# Emit one picker row per running Claude that lives in a tmux pane.
#
# Reads ~/.claude/sessions/<pid>.json rather than shelling out to
# `claude agents --json`, which costs ~210ms of Node startup. Falls back to the
# CLI when those files are absent. `statusUpdatedAt` gives last-activity
# directly, so no transcript glob is needed.
#
# The pane an agent occupies comes from its own environment: tmux exports
# TMUX_PANE into every pane and every child inherits it -- through the shell,
# through an editor, into Claude. So an agent inside an embedded terminal
# (nvim `:terminal`, sidekick.nvim) needs no special handling; it reports the
# pane of the editor hosting it. Nothing here walks the process tree, and
# nothing keys off `tty`: a tty is recycled by the OS, whereas tmux never
# reuses a `%N` pane id within a server.
#
# TMUX also carries the server pid, so agents belonging to another tmux server
# are skipped rather than mis-joined onto a same-numbered pane here.
#
# A session file outlives an agent killed with SIGKILL, so a recycled PID could
# surface a bogus row that ctrl-x would then kill. The executable path is
# checked to rule that out. (procStart cannot be compared against ps lstart:
# the former is UTC, the latter local time.)
#
#   Row: rank \t pane_id \t pid \t kind \t icon \t age \t loc \t path
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# pid \t status \t cwd \t statusUpdatedAt(ms)
rows="$(jq -r -s '
  .[] | select(.kind == "interactive")
      | [.pid, .status, .cwd, (.statusUpdatedAt // .updatedAt // 0)]
      | @tsv' "$base"/sessions/*.json 2>/dev/null)"

# Fallback: no session files (older Claude Code, or the layout moved).
if [ -z "$rows" ]; then
  rows="$(claude agents --json 2>/dev/null |
    jq -r '.[] | select(.kind == "interactive") | [.pid, .status, .cwd, 0] | @tsv' 2>/dev/null)"
fi
[ -n "$rows" ] || exit 0

pids="$(printf '%s\n' "$rows" | cut -f1 | paste -sd, -)"

# E: pid \t pane \t server-pid \t exe   -- one row per agent, from its environment.
agent_env() {
  if [ -r /proc/self/environ ]; then
    # Linux: read the environment directly, no ps.
    printf '%s\n' "$rows" | cut -f1 | while IFS= read -r p; do
      [ -r "/proc/$p/environ" ] || continue
      tr '\0' '\n' <"/proc/$p/environ" |
        awk -v p="$p" -v exe="$(tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | cut -d' ' -f1)" '
          /^TMUX_PANE=/ { pane = substr($0, 11) }
          /^TMUX=/      { split(substr($0, 6), t, ","); srv = t[2] }
          END           { if (pane != "") print "E\t" p "\t" pane "\t" srv "\t" exe }'
    done
  else
    # BSD/macOS: -E appends the environment to the command column.
    ps -Eww -o pid=,command= -p "$pids" 2>/dev/null | awk '{
      pid = $1; exe = $2; pane = ""; srv = ""
      for (i = 3; i <= NF; i++) {
        if      ($i ~ /^TMUX_PANE=/) pane = substr($i, 11)
        else if ($i ~ /^TMUX=/)      { split(substr($i, 6), t, ","); srv = t[2] }
      }
      if (pane != "") print "E\t" pid "\t" pane "\t" srv "\t" exe
    }'
  fi
}

{
  agent_env
  tmux list-panes -a -F $'T\t#{pane_id}\t#{session_name}\t#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null
  printf '%s\n' "$rows" | sed $'s/^/A\t/'
} | awk -F'\t' -v now="$(date +%s)" -v home="$HOME" \
  -v server="$(tmux display-message -p '#{pid}' 2>/dev/null)" \
  -v prefix="$(get_tmux_option @claude_session_prefix 'claude-')" '
  $1 == "E" { pane_of[$2] = $3; srv_of[$2] = $4; exe_of[$2] = $5; next }
  $1 == "T" { sess[$2] = $3; loc[$2] = $4; next }
  $1 == "A" {
    pid = $2; status = $3; cwd = $4; upd = $5

    p = pane_of[pid]
    if (p == "" || !(p in sess)) next             # not in a pane of this server
    if (server != "" && srv_of[pid] != "" && srv_of[pid] != server) next

    # Stale file + recycled PID. Fail open: only drop when we can positively
    # identify the live process as something other than a Claude.
    e = exe_of[pid]
    if (e != "" && e !~ /claude|node/) next

    if      (status == "waiting") { icon = "\033[33m●\033[0m waiting"; rank = 0 }
    else if (status == "idle")    { icon = "\033[32m●\033[0m idle   "; rank = 1 }
    else if (status == "busy")    { icon = "\033[31m●\033[0m working"; rank = 3 }
    else                          { icon = "\033[90m●\033[0m   ?    "; rank = 2 }

    age = (upd > 0) ? int((now - upd / 1000) / 60) "m" : "-"
    kind = (index(sess[p], prefix) == 1) ? "dedicated" : "loose"

    path = cwd
    if (index(path, home) == 1) path = "~" substr(path, length(home) + 1)

    printf "%s\t%s\t%s\t%s\t%s\t%5s\t%s\t%s\n",
      rank, p, pid, kind, icon, age, loc[p], path
  }
' | sort -t$'\t' -k1,1n -k6,6n
