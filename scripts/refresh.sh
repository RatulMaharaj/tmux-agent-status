#!/usr/bin/env bash
# refresh.sh — scan every pane, detect which agent (if any) is running AND what
# it's doing, write a status badge into @agent_status per window, optionally
# rename the window, and fire a system notification on important transitions
# (agent finished while you were away / agent now needs you).
#
# Run both on-demand (the `w` binding) and continuously (scripts/daemon.sh).
# A lock serializes overlapping runs so notifications fire exactly once.
#
# Written for bash 3.2 (macOS system bash): no associative arrays.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/classify.sh
. "$SCRIPT_DIR/../lib/classify.sh"

tmux_opt() { # tmux_opt <@option> <default>
  local v; v="$(tmux show-option -gqv "$1" 2>/dev/null)"
  if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agent-status"
CACHE="$CACHE_DIR/state"
NEW="$CACHE.new"
LOCKDIR="$CACHE_DIR/refresh.lock"
mkdir -p "$CACHE_DIR"

# --- Serialize: only one refresh at a time (binding vs daemon) ---------------
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  oldpid="$(cat "$LOCKDIR/pid" 2>/dev/null)"
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    exit 0                                  # another refresh is running
  fi
  rm -rf "$LOCKDIR"; mkdir "$LOCKDIR" 2>/dev/null || exit 0   # steal stale lock
fi
echo $$ > "$LOCKDIR/pid"
trap 'rm -rf "$LOCKDIR"' EXIT

# Cold start (no prior cache) → don't notify, or we'd alert for every existing
# blocked/done agent the moment the daemon launches.
NO_NOTIFY=0
[ -f "$CACHE" ] || NO_NOTIFY=1
: > "$NEW"

GLOBAL_ICON="$(tmux_opt @agent_status_icon 🤖)"
RENAME="$(tmux_opt @agent_status_rename off)"
AGENTS_ORDER="$(agent_status_agents)"
NOTIFY="$(tmux_opt @agent_status_notify 'done blocked')"   # states that notify
SOUND="$(tmux_opt @agent_status_sound Glass)"              # empty = silent

# --- State -> bracketed label (colored by the chooser/status-bar format) -----
L_WORKING="$(tmux_opt @agent_status_label_working working)"
L_BLOCKED="$(tmux_opt @agent_status_label_blocked blocked)"
L_DONE="$(tmux_opt @agent_status_label_done done)"
L_IDLE="$(tmux_opt @agent_status_label_idle idle)"
status_label() {
  case "$1" in
    working) printf '%s' "$L_WORKING" ;;
    blocked) printf '%s' "$L_BLOCKED" ;;
    done)    printf '%s' "$L_DONE" ;;
    idle)    printf '%s' "$L_IDLE" ;;
    *)       printf '' ;;
  esac
}
state_rank() {
  case "$1" in
    blocked) echo 4 ;; working) echo 3 ;; done) echo 2 ;; idle) echo 1 ;; *) echo 0 ;;
  esac
}
icon_for() {
  local v; v="$(tmux show-option -gqv "@agent_status_icon_$1" 2>/dev/null)"
  if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$GLOBAL_ICON"; fi
}

# --- Notifications (macOS) ---------------------------------------------------
should_notify() { case " $NOTIFY " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
notify() { # notify <title> <message>
  local title msg
  title="$(printf '%s' "$1" | tr -d '"\\')"
  msg="$(printf '%s' "$2" | tr -d '"\\')"
  if [ -n "$SOUND" ]; then
    osascript -e "display notification \"$msg\" with title \"$title\" sound name \"$SOUND\"" >/dev/null 2>&1 &
  else
    osascript -e "display notification \"$msg\" with title \"$title\"" >/dev/null 2>&1 &
  fi
}

prev_state() { # prev_state <pane_id>
  [ -f "$CACHE" ] || return 0
  awk -v p="$1" '$1==p {print $2; exit}' "$CACHE"
}
# display_state <raw> <prev> <window_active>
display_state() {
  local raw="$1" prev="$2" active="$3"
  case "$raw" in
    working) echo working ;;
    blocked) echo blocked ;;
    unknown) echo unknown ;;
    *) if [ "$active" = "1" ]; then echo idle
       elif [ "$prev" = "working" ] || [ "$prev" = "done" ]; then echo done
       else echo idle; fi ;;
  esac
}

# --- Optional window rename, with save/restore of the original name ----------
rename_present() { # rename_present <window_id> <agent>
  [ "$RENAME" = "window" ] || return 0
  local window_id="$1" agent="$2" cur prev auto
  cur="$(tmux display-message -p -t "$window_id" '#{window_name}')"
  [ "$cur" = "$agent" ] && return 0
  prev="$(tmux show-option -wqv -t "$window_id" @agent_status_prev_name 2>/dev/null)"
  if [ -z "$prev" ]; then
    tmux set-option -w -t "$window_id" @agent_status_prev_name "$cur"
    auto="$(tmux show-option -wqv -t "$window_id" automatic-rename 2>/dev/null)"
    tmux set-option -w -t "$window_id" @agent_status_auto_prev "${auto:-unset}"
  fi
  tmux set-option -w -t "$window_id" automatic-rename off
  tmux rename-window -t "$window_id" "$agent"
}
rename_absent() { # rename_absent <window_id>
  [ "$RENAME" = "window" ] || return 0
  local window_id="$1" prev auto
  prev="$(tmux show-option -wqv -t "$window_id" @agent_status_prev_name 2>/dev/null)"
  [ -n "$prev" ] || return 0
  tmux rename-window -t "$window_id" "$prev"
  tmux set-option -wu -t "$window_id" @agent_status_prev_name
  auto="$(tmux show-option -wqv -t "$window_id" @agent_status_auto_prev 2>/dev/null)"
  if [ -z "$auto" ] || [ "$auto" = "unset" ]; then
    tmux set-option -wu -t "$window_id" automatic-rename 2>/dev/null
  else
    tmux set-option -w -t "$window_id" automatic-rename "$auto"
  fi
  tmux set-option -wu -t "$window_id" @agent_status_auto_prev 2>/dev/null
}

# --- Scan every window, aggregating over its panes ---------------------------
tmux list-windows -a -F '#{window_id} #{window_active} #{session_name} #{window_index} #{window_name}' |
while read -r window_id window_active session_name window_index window_name; do
  [ -n "$window_id" ] || continue

  found=" "
  best_state="none"
  best_rank=-1

  while read -r pane_id pane_cmd pane_tty; do
    [ -n "$pane_id" ] || continue
    agent="$(classify_pane "$window_id" "$window_index" "$pane_id" "$pane_cmd" "$window_name" "$pane_tty")"
    [ "$agent" = "none" ] && continue
    case "$found" in *" $agent "*) ;; *) found="$found$agent " ;; esac

    prev="$(prev_state "$pane_id")"
    raw="$(classify_state "$pane_id" "$agent")"
    disp="$(display_state "$raw" "$prev" "$window_active")"
    printf '%s %s\n' "$pane_id" "$disp" >> "$NEW"

    # Fire notifications on the meaningful edges.
    if [ "$NO_NOTIFY" = 0 ]; then
      if [ "$disp" = "done" ] && [ "$prev" = "working" ] && should_notify done; then
        notify "🤖 $agent finished" "$window_name — $session_name"
      elif [ "$disp" = "blocked" ] && [ "$prev" != "blocked" ] && should_notify blocked; then
        notify "🤖 $agent needs you" "$window_name — $session_name"
      fi
    fi

    r="$(state_rank "$disp")"
    if [ "$r" -gt "$best_rank" ]; then best_rank="$r"; best_state="$disp"; fi
  done < <(tmux list-panes -t "$window_id" -F '#{pane_id} #{pane_current_command} #{pane_tty}')

  chosen=""
  for a in $AGENTS_ORDER; do
    case "$found" in *" $a "*) chosen="$a"; break ;; esac
  done

  if [ -n "$chosen" ]; then
    icon="$(icon_for "$chosen")"
    label="$(status_label "$best_state")"
    if [ -n "$label" ]; then
      tmux set-option -w -t "$window_id" @agent_status "$icon ($label) "
      tmux set-option -w -t "$window_id" @agent_status_state "$best_state"
    else
      tmux set-option -w -t "$window_id" @agent_status "$icon "
      tmux set-option -wu -t "$window_id" @agent_status_state 2>/dev/null
    fi
    rename_present "$window_id" "$chosen"
  else
    tmux set-option -wu -t "$window_id" @agent_status 2>/dev/null
    tmux set-option -wu -t "$window_id" @agent_status_state 2>/dev/null
    rename_absent "$window_id"
  fi
done

mv -f "$NEW" "$CACHE" 2>/dev/null || true
