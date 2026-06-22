#!/usr/bin/env bash
# test-notification.sh — diagnose agent-status sound & notifications.
#
# Run this DIRECTLY in your terminal (so it shares your audio session):
#   ~/Projects/tmux-agent-status/scripts/test-notification.sh
set -u

tmux_opt() { tmux show-option -gqv "$1" 2>/dev/null; }
SOUND="$(tmux_opt @agent_status_sound)"; [ -n "$SOUND" ] || SOUND="Glass"

# Same mapping as refresh.sh's play_sound().
resolve_sound() {
  case "$1" in
    "")                  return 1 ;;
    */*)                 printf '%s' "$1" ;;
    *.aiff|*.wav|*.m4a)  printf '/System/Library/Sounds/%s' "$1" ;;
    *)                   printf '/System/Library/Sounds/%s.aiff' "$1" ;;
  esac
}
F="$(resolve_sound "$SOUND")"

echo "tmux-agent-status — notification test"
echo "====================================="
echo "Configured @agent_status_sound : ${SOUND}"
echo "Resolved sound file            : ${F:-<silent>}"
echo

echo "[1/4] System output volume / mute"
osascript -e 'set s to get volume settings' \
          -e 'return "  output volume=" & (output volume of s) & "  muted=" & (output muted of s)' \
  2>/dev/null || echo "  (could not read volume)"
echo

echo "[2/4] Playing the sound with afplay — you should HEAR this now…"
if [ -n "$F" ] && [ -f "$F" ]; then
  if afplay "$F"; then echo "  afplay: ok"; else echo "  afplay: FAILED (exit $?)"; fi
else
  echo "  sound file not found: ${F:-<none>}"
  echo "  available system sounds (use any with: set -g @agent_status_sound <name>):"
  ls /System/Library/Sounds/ 2>/dev/null | sed 's/\.aiff$//;s/^/    /'
fi
echo

echo "[3/4] Firing a notification banner via osascript…"
if osascript -e "display notification \"banners work\" with title \"🤖 tmux-agent-status test\""; then
  echo "  osascript: ok (look top-right of your screen)"
fi
echo

echo "[4/4] Recent notifications fired by the daemon (if any)"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agent-status/notify.log"
if [ -f "$LOG" ]; then tail -5 "$LOG" | sed 's/^/  /'; else echo "  (no notify.log yet — nothing has fired)"; fi
echo

cat <<'TIPS'
Troubleshooting
---------------
• Heard it here but NOT from agents? The tmux server likely started without an
  audio session. Restart it:  tmux kill-server   (then reopen tmux).
• No sound here either? Unmute / raise volume; confirm the resolved file exists,
  or pick another:  set -g @agent_status_sound Ping
• No banner? System Settings → Notifications → "Script Editor" → Allow
  Notifications (osascript banners post as Script Editor). Also turn off any
  Focus / Do Not Disturb.
• Custom sound: point @agent_status_sound at any .aiff/.wav path.
TIPS
