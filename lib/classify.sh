#!/usr/bin/env bash
# classify.sh — the ONE seam between the plugin pipeline and agent detection:
# which coding agent (if any) is running in a pane, and what it's doing.
#
# The state taxonomy and colours (working / blocked / done / idle) are adapted
# from herdr (https://github.com/ogulcancelik/herdr), an AGPL project — concept
# only, no code reused. This file is original MIT-licensed bash.
#
# Why look at the tty and not pane_current_command? Claude Code renames its
# process to its version string (e.g. "2.1.185"), so tmux's #{pane_current_command}
# reports "2.1.185", not "claude". But `ps -t <tty> -o command` still shows the
# real argv ("claude"). So we inspect every process on the pane's tty and match
# its command basename against the configured agent list, preferring whichever is
# in the foreground process group (state contains "+").
#
# classify_pane <window_id> <window_index> <pane_id> <pane_cmd> <window_name> <pane_tty>
#   echoes the detected agent name (e.g. "claude"), or "none".
#
# Aggregation priority (decided in refresh.sh): first agent, in @agent_status_agents
# order, that is running anywhere in the window.

# Space-separated agent program names to detect, in priority order.
# Override with:  set -g @agent_status_agents "claude codex opencode aider"
agent_status_agents() {
  local v; v="$(tmux show-option -gqv @agent_status_agents 2>/dev/null)"
  if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "claude codex opencode"; fi
}

classify_pane() {
  local pane_tty="$6"
  local short="${pane_tty#/dev/}"
  [ -n "$short" ] || { echo none; return; }

  # All processes sharing this pane's tty: "<state> <command...>" per line.
  local procs
  procs="$(ps -t "$short" -o state=,command= 2>/dev/null)"
  [ -n "$procs" ] || { echo none; return; }

  local agents; agents="$(agent_status_agents)"
  local fg_set=" " any_set=" "   # space-padded membership sets (bash 3.2: no assoc arrays)

  local state rest cmd base agent
  # read splits on whitespace: state = first field, rest = the command (+args).
  while read -r state rest; do
    [ -n "$rest" ] || continue
    cmd="${rest%% *}"            # first token of the command (the program)
    base="${cmd##*/}"            # its basename
    for agent in $agents; do
      [ "$base" = "$agent" ] || continue
      case "$state" in
        *+*) case "$fg_set"  in *" $agent "*) ;; *) fg_set="$fg_set$agent " ;; esac ;;
        *)   case "$any_set" in *" $agent "*) ;; *) any_set="$any_set$agent " ;; esac ;;
      esac
    done
  done <<EOF
$procs
EOF

  # Prefer a foreground agent; fall back to any. Pick by configured priority.
  for agent in $agents; do
    case "$fg_set" in *" $agent "*) echo "$agent"; return ;; esac
  done
  for agent in $agents; do
    case "$any_set" in *" $agent "*) echo "$agent"; return ;; esac
  done
  echo none
}

# classify_state <pane_id> <agent> -> working | blocked | waiting | unknown
#
# Reads the pane's visible screen and matches the agent's TUI. We only have
# reliable markers for Claude Code today; other agents return "unknown" (the
# window still shows the agent icon, just no status dot). Markers, from real
# Claude output:
#   working  — live spinner "Tempering… (14s · ↓ 607 tokens)" or "esc to interrupt"
#              (note: a *completed* "✻ Brewed for 20m 22s" line has no "… (" timer)
#   blocked  — a numbered selection menu "❯ 1. Yes" (permission / plan prompts)
#   waiting  — agent is at its prompt, nothing running and nothing to approve
classify_state() {
  local pane_id="$1" agent="$2" buf
  case "$agent" in
    claude) ;;                       # supported below
    *) echo unknown; return ;;       # no heuristics for this agent yet
  esac
  buf="$(tmux capture-pane -p -t "$pane_id" 2>/dev/null)"
  [ -n "$buf" ] || { echo unknown; return; }
  if printf '%s\n' "$buf" | grep -qE 'esc to interrupt|…[[:space:]]*\([0-9]'; then
    echo working; return
  fi
  if printf '%s\n' "$buf" | grep -qE '❯[[:space:]]+[0-9]+\.'; then
    echo blocked; return
  fi
  echo waiting
}
