#!/usr/bin/env bash
# test-notification.sh — diagnose agent-status sound & notifications.
#
# Run it in your terminal:
#   ~/Projects/tmux-agent-status/scripts/test-notification.sh
set -u

tmux_opt() { tmux show-option -gqv "$1" 2>/dev/null; }
SOUND="$(tmux_opt @agent_status_sound)"; [ -n "$SOUND" ] || SOUND="Glass"

echo "tmux-agent-status — notification test"
echo "====================================="
echo "Configured @agent_status_sound : ${SOUND}"
echo

# This mirrors EXACTLY what the daemon's notify() does.
echo "[1/3] Notification banner + sound (the real path the daemon uses)…"
if command -v terminal-notifier >/dev/null 2>&1; then
  echo "      using terminal-notifier (good — reliable identity & permission)"
  echo "      → You should SEE a banner and HEAR \"${SOUND}\"."
  terminal-notifier -title "🤖 tmux-agent-status test" -message "agent finished" -sound "${SOUND}" \
    && echo "      terminal-notifier returned ok"
else
  echo "      using osascript (terminal-notifier NOT installed)"
  echo "      → You should SEE a banner and HEAR \"${SOUND}\" — IF notifications are allowed."
  echo "      NOTE: osascript returns ok even when the banner is blocked/suppressed."
  osascript -e "display notification \"agent finished\" with title \"🤖 tmux-agent-status test\" sound name \"${SOUND}\"" \
    && echo "      osascript returned ok"
fi
echo

# afplay only works when the process has an audio session. Under tmux the server
# often has none (afplay fails with 'AudioQueueStart'); that's expected and is
# why the daemon does NOT rely on afplay.
echo "[2/3] Direct afplay (informational; expected to FAIL inside tmux)…"
F="/System/Library/Sounds/${SOUND}.aiff"; [ -f "$F" ] || F="/System/Library/Sounds/Glass.aiff"
if afplay "$F" 2>/dev/null; then
  echo "      afplay ok — this process has an audio session"
else
  echo "      afplay failed — no audio session here (normal under tmux; Notification Center above is what matters)"
fi
echo

echo "[3/3] Recent notifications fired by the daemon (if any)"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agent-status/notify.log"
if [ -f "$LOG" ]; then tail -5 "$LOG" | sed 's/^/  /'; else echo "  (no notify.log yet — nothing has fired)"; fi
echo

cat <<'TIPS'
If you got NO banner and NO sound in step [1]
---------------------------------------------
Notifications are blocked for the scripting host. Fix:
  System Settings → Notifications → find "Script Editor" (it appears after the
  first attempt above) → turn ON Allow Notifications, and set the alert style.
  Also disable Focus / Do Not Disturb.

Banner shows but NO sound?
  • Unmute / raise system volume.
  • Make sure "Play sound for notifications" is enabled for that app.
  • Try another sound:  set -g @agent_status_sound Ping   (then reload tmux)

Prefer a dedicated notifier?
  brew install terminal-notifier   — more reliable identity/permissions than
  osascript. (Tell me and I'll switch the plugin to use it if present.)
TIPS
