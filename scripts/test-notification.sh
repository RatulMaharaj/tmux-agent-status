#!/usr/bin/env bash
# test-notification.sh — the canonical way to test agent-status notifications.
# Uses the SAME delivery as the daemon's notify(): terminal-notifier if present,
# else osascript; the sound is played by the notification system (works from
# inside tmux, where afplay often can't).
#
# Usage:
#   test-notification.sh            # full diagnostic, using your configured sound
#   test-notification.sh <Sound>    # fire one test notification with <Sound> (e.g. Ping)
#   test-notification.sh sounds     # audition every system sound, one banner each
set -u

tmux_opt() { tmux show-option -gqv "$1" 2>/dev/null; }
CONFIGURED="$(tmux_opt @agent_status_sound)"; [ -n "$CONFIGURED" ] || CONFIGURED="Glass"
backend() { command -v terminal-notifier >/dev/null 2>&1 && echo terminal-notifier || echo osascript; }

# THE delivery path (identical to refresh.sh notify()).
send() { # send <title> <message> <sound>
  local title msg sound
  title="$(printf '%s' "$1" | tr -d '"\\')"
  msg="$(printf '%s' "$2" | tr -d '"\\')"
  sound="$3"
  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$title" -message "$msg" ${sound:+-sound "$sound"} >/dev/null 2>&1
  else
    local sc=""; [ -n "$sound" ] && sc=" sound name \"$sound\""
    osascript -e "display notification \"$msg\" with title \"$title\"$sc" >/dev/null 2>&1
  fi
}
list_sounds() { ls /System/Library/Sounds/ 2>/dev/null | sed 's/\.aiff$//'; }
sound_file() { # name|path -> file path
  case "$1" in
    */*)                printf '%s' "$1" ;;
    *.aiff|*.wav|*.m4a) printf '/System/Library/Sounds/%s' "$1" ;;
    *)                  printf '/System/Library/Sounds/%s.aiff' "$1" ;;
  esac
}
# Audition uses afplay (instant, no notification throttling — macOS coalesces
# rapid repeat banners, which silences quick back-to-back notification tests).
preview() { local f; f="$(sound_file "$1")"; [ -f "$f" ] && afplay "$f" 2>/dev/null; }

case "${1:-}" in
  sounds|--sounds|--list)
    echo "Auditioning system sounds with afplay (you'll hear each)…"
    for s in $(list_sounds); do printf '  ♪ %-10s' "$s"; preview "$s"; echo; done
    echo
    echo "Set your pick with:  set -g @agent_status_sound <Name>   (then reload tmux)"
    echo "Currently configured: $CONFIGURED"
    exit 0
    ;;
  ?*)
    echo "Previewing sound: $1"
    preview "$1" || echo "  (couldn't play $(sound_file "$1"))"
    echo "Like it? Set it with:  set -g @agent_status_sound $1   (then reload tmux)"
    exit 0
    ;;
esac

# --- no args: full diagnostic -----------------------------------------------
echo "tmux-agent-status — notification test"
echo "====================================="
echo "Backend            : $(backend)"
echo "Configured sound   : $CONFIGURED"
echo

echo "[1/3] Fire a banner + sound (the real path the daemon uses)…"
echo "      → You should SEE a banner and HEAR \"$CONFIGURED\"."
send "🤖 tmux-agent-status test" "agent finished" "$CONFIGURED" && echo "      sent ok"
echo

echo "[2/3] Direct afplay (informational — only works with an audio session)…"
F="/System/Library/Sounds/${CONFIGURED}.aiff"; [ -f "$F" ] || F="/System/Library/Sounds/Glass.aiff"
if afplay "$F" 2>/dev/null; then echo "      afplay ok"; else echo "      afplay failed (normal inside tmux; not what the daemon relies on)"; fi
echo

echo "[3/3] Recent notifications fired by the daemon (if any)"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agent-status/notify.log"
if [ -f "$LOG" ]; then tail -5 "$LOG" | sed 's/^/  /'; else echo "  (none yet)"; fi
echo

cat <<'TIPS'
Try other sounds:  test-notification.sh sounds   (or: test-notification.sh Ping)

No banner?
  • Sound plays but no banner → alert style is off. System Settings →
    Notifications → terminal-notifier → set Alert style to Banners/Alerts.
  • Nothing at all → turn ON Allow Notifications for terminal-notifier, and
    disable Focus / Do Not Disturb.
No sound? Unmute / raise volume, or pick another:  test-notification.sh sounds
TIPS
