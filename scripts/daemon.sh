#!/usr/bin/env bash
# daemon.sh — background poller. Re-runs refresh.sh every @agent_status_interval
# seconds so badges stay live (status bar + chooser) and notifications fire even
# when you're not looking. Started detached by agent-status.tmux.
#
# Single-instance: each daemon claims ownership by writing its PID to the global
# @agent_status_daemon_pid option. If a newer daemon starts (e.g. config reload)
# it overwrites that option; older daemons notice they're no longer the owner on
# their next tick and exit. The daemon also exits when the tmux server is gone.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFRESH="$SCRIPT_DIR/refresh.sh"

# Claim ownership.
tmux set-option -g @agent_status_daemon_pid "$$" 2>/dev/null || exit 0

while tmux has-session 2>/dev/null; do
  owner="$(tmux show-option -gqv @agent_status_daemon_pid 2>/dev/null)"
  [ "$owner" = "$$" ] || exit 0          # a newer daemon took over

  "$REFRESH" >/dev/null 2>&1
  tmux refresh-client -S 2>/dev/null     # redraw status lines with fresh values

  interval="$(tmux show-option -gqv @agent_status_interval 2>/dev/null)"
  sleep "${interval:-3}"
done
