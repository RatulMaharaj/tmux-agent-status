#!/usr/bin/env bash
# demo-notification.sh — fire the actual agent notifications on demand, so you
# can confirm banners + sound work. Uses the SAME delivery as the daemon's
# notify(): terminal-notifier if installed, else osascript; sound played by the
# notification system (works from inside tmux).
#
#   ~/Projects/tmux-agent-status/scripts/demo-notification.sh
set -u

SOUND="$(tmux show-option -gqv @agent_status_sound 2>/dev/null)"; [ -n "$SOUND" ] || SOUND="Glass"

send() { # send <title> <message>
  local title msg
  title="$(printf '%s' "$1" | tr -d '"\\')"
  msg="$(printf '%s' "$2" | tr -d '"\\')"
  if command -v terminal-notifier >/dev/null 2>&1; then
    echo "  → terminal-notifier: $title — $msg"
    terminal-notifier -title "$title" -message "$msg" ${SOUND:+-sound "$SOUND"} >/dev/null 2>&1
  else
    echo "  → osascript: $title — $msg"
    local sc=""; [ -n "$SOUND" ] && sc=" sound name \"$SOUND\""
    osascript -e "display notification \"$msg\" with title \"$title\"$sc" >/dev/null 2>&1
  fi
}

echo "Firing the two agent notifications (sound: $SOUND)…"
echo "Watch the top-right of your screen."
send "🤖 claude finished" "demo — you should see this when an agent completes"
sleep 2
send "🤖 claude needs you" "demo — you'd see this when an agent hits a prompt"
echo "Done. Saw two banners and heard the sound twice? Notifications are working."
echo "(No banner? Allow notifications for this app in System Settings → Notifications.)"
