#!/usr/bin/env bash
# agent-status.tmux — plugin entry point (TPM-style).
#
# Install by adding ONE line to ~/.tmux.conf:
#   run-shell '/path/to/tmux-agent-status/agent-status.tmux'
# then reload: tmux source-file ~/.tmux.conf
#
# Wires up three things:
#   1. C-a w  -> refresh + choose-tree, badges colored by agent state.
#   2. A live badge in the status bar (appended to window-status-format).
#   3. A background poller (scripts/daemon.sh) that keeps badges fresh and
#      fires notifications when an agent finishes / needs you.
set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFRESH="$CURRENT_DIR/scripts/refresh.sh"
DAEMON="$CURRENT_DIR/scripts/daemon.sh"

opt() { # opt <@option> <default>
  local v; v="$(tmux show-option -gqv "$1" 2>/dev/null)"
  if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}

KEY="$(opt @agent_status_key w)"

# State -> colour (any tmux colour: named, colourNNN, or #RRGGBB).
CW="$(opt @agent_status_color_working yellow)"
CB="$(opt @agent_status_color_blocked red)"
CD="$(opt @agent_status_color_done blue)"
CI="$(opt @agent_status_color_idle green)"

# Nested conditional resolving @agent_status_state -> colour. tmux expands the
# inner #{...} before the #[fg=...] style is applied at draw time.
S='#{@agent_status_state}'
COLOR="#{?#{==:$S,working},$CW,#{?#{==:$S,blocked},$CB,#{?#{==:$S,done},$CD,#{?#{==:$S,idle},$CI,default}}}}"

# Chooser always shows icon + label; the status bar can hide the icon (label
# only) via @agent_status_statusbar_icon off.
CHOOSER_BADGE="#[fg=$COLOR]#{@agent_status}#[default]"
if [ "$(opt @agent_status_statusbar_icon on)" = "off" ]; then
  BAR_BADGE="#[fg=$COLOR]#{@agent_status_text}#[default]"
else
  BAR_BADGE="#[fg=$COLOR]#{@agent_status}#[default]"
fi

# --- 1. Chooser key ----------------------------------------------------------
WINROW="$CHOOSER_BADGE#{window_index}: #{window_name}#{window_flags}"
FORMAT="#{?pane_format,#{pane_current_command},#{?window_format,$WINROW,#{session_name}}}"
tmux bind-key "$KEY" run-shell "$REFRESH" '\;' choose-tree -Zw -F "$FORMAT"

# --- 2. Live status-bar badge ------------------------------------------------
# Append the badge to the window-status formats, preserving the user's theme.
# We re-capture the original whenever the current value isn't already badged
# (true right after `source-file`, which re-applies the user's own format).
if [ "$(opt @agent_status_statusbar on)" != "off" ]; then
  for which in window-status-format window-status-current-format; do
    saved_opt="@agent_status_orig_${which}"
    cur="$(tmux show-option -gqv "$which" 2>/dev/null)"
    case "$cur" in
      *'@agent_status'*) orig="$(tmux show-option -gqv "$saved_opt" 2>/dev/null)" ;;
      *) orig="$cur"; tmux set-option -g "$saved_opt" "$orig" ;;
    esac
    tmux set-option -g "$which" "${orig}$BAR_BADGE"
  done
fi

# --- 3. Background poller -----------------------------------------------------
if [ "$(opt @agent_status_poll on)" != "off" ]; then
  tmux run-shell -b "$DAEMON"
fi

# Apply once immediately so badges show without waiting for the first tick.
tmux run-shell -b "$REFRESH"
