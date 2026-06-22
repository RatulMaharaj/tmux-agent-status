# tmux-agent-status

See at a glance which of your tmux windows are running a coding agent — right in
the window chooser (`prefix + w`).

Pressing the chooser key refreshes every window, detects whether an agent
(Claude Code, Codex, opencode, …) is running in any of its panes and what it's
doing, then prepends a badge — the agent icon plus a bracketed status label,
colored by state — to windows that have one:

```
🤖 (working) 1: api      ← label in yellow
🤖 (blocked) 2: build    ← label in red — needs your input
🤖 (done)    3: worker   ← label in blue — finished, you haven't looked yet
🤖 (idle)    4: notes    ← label in green — finished and seen
             5: shell    ← no agent (plain shell)
```

Only windows actually running an agent get a badge. (The emoji keeps its own
color; the bracketed label is what gets tinted.)

## Status states

| Label       | Colour | State   | Meaning                                            |
|-------------|--------|---------|----------------------------------------------------|
| `(working)` | yellow | working | actively running (live spinner / "esc to interrupt") |
| `(blocked)` | red    | blocked | a prompt is waiting on you (e.g. `❯ 1. Yes`)       |
| `(done)`    | blue   | done    | finished since you last looked (working → idle)    |
| `(idle)`    | green  | idle    | at the prompt, and you've seen it                  |

**done → idle** flips automatically once you actually view the window (its
session is attached and the window is active), so `(done)` highlights "an agent
finished while you were away." The transition is tracked in a tiny per-pane
cache under `$XDG_CACHE_HOME/tmux-agent-status/state`.

Status detection currently has markers for **Claude Code**. Other agents still
get a presence badge (their icon, no status label) until markers are added.

> The state taxonomy and colours are adapted from
> [herdr](https://github.com/ogulcancelik/herdr) (an AGPL project) — concept
> only, no code is reused. This plugin is original MIT-licensed bash.

## Realtime updates & notifications

A small background poller (`scripts/daemon.sh`) re-scans every few seconds, so:

- the **status bar** shows a live colored badge on every window (no need to open
  the chooser) — the badge is appended to your `window-status-format`, preserving
  your existing theme;
- you get a **system notification** (macOS) when an agent **finishes while you're
  on another window** (working → done) or **becomes blocked** waiting on you.
  Nothing fires while you're watching the window finish.

The poller is single-instance (a reload cleanly replaces it) and exits when the
tmux server stops.

```tmux
set -g @agent_status_interval 3              # poll seconds (default 3)
set -g @agent_status_poll      on            # off to disable the poller
set -g @agent_status_statusbar on            # off to keep badges out of the status bar
set -g @agent_status_notify    "done blocked"  # states that notify; "" to silence
set -g @agent_status_sound     Glass         # macOS sound name; "" for silent banner
```

## How detection works

Claude Code renames its own process to its version string (e.g. `2.1.185`), so
`#{pane_current_command}` is unreliable. Instead, for each pane we inspect the
processes on its **tty** (`ps -t <tty>`) and match each process's command
basename against a configurable agent list, preferring the foreground process.
This catches agents regardless of how tmux labels the pane.

## Install

Add one line to `~/.tmux.conf`:

```tmux
run-shell '~/Projects/tmux-agent-status/agent-status.tmux'
```

Reload tmux:

```sh
tmux source-file ~/.tmux.conf
```

Now press `prefix + w` (e.g. `C-a w`). Windows running an agent show an icon.

(TPM users: this is a standard `*.tmux` plugin and also loads under TPM.)

## Configuration

All optional — set in `~/.tmux.conf` before the `run-shell` line.

### Which agents to detect

```tmux
# Program names to look for, in priority order (basename of the process).
set -g @agent_status_agents "claude codex opencode"
```

Add your own, e.g. `"claude codex opencode aider gemini"`.

### Icons (customisable)

```tmux
set -g @agent_status_icon          🤖     # fallback icon for any agent
set -g @agent_status_icon_claude   ✳️     # per-agent override
set -g @agent_status_icon_codex    🔷
set -g @agent_status_icon_opencode 🟢
```

A per-agent icon (`@agent_status_icon_<name>`) wins; otherwise the global
`@agent_status_icon` is used. With per-agent icons set, the chooser shows a
different icon per agent. Set `@agent_status_icon ""` for label-only badges
(no agent icon).

### Status labels and colours

```tmux
# Bracketed label text per state
set -g @agent_status_label_working working
set -g @agent_status_label_blocked blocked
set -g @agent_status_label_done    done
set -g @agent_status_label_idle    idle

# Colour per state (any tmux colour: named, colourNNN, or #RRGGBB)
set -g @agent_status_color_working yellow
set -g @agent_status_color_blocked red
set -g @agent_status_color_done    blue
set -g @agent_status_color_idle    green
```

### Auto-rename the window to the agent

```tmux
set -g @agent_status_rename window     # off (default) | window
```

When enabled, a window running an agent is renamed to the agent (e.g.
`claude`). The original window name and its `automatic-rename` setting are saved
and **restored automatically** when the agent exits — so your hand-named windows
come back unchanged. Windows without an agent are never touched.

### Chooser key

```tmux
set -g @agent_status_key w     # the prefix key to wrap (default: w)
```

## How it works

- **`agent-status.tmux`** — entry point. Rebinds the chooser key, appends the
  live badge to the status-bar formats, and starts the background poller.
- **`scripts/refresh.sh`** — for each window, scans its panes, picks the
  highest-priority detected agent and state, writes `@agent_status` /
  `@agent_status_state`, fires notifications on transitions, and optionally
  renames the window. A lock serializes the poller and the on-demand run.
- **`scripts/daemon.sh`** — the background poller loop.
- **`lib/classify.sh`** — `classify_pane()` (which agent) and `classify_state()`
  (what it's doing): the detection seam. Swap these to change detection.

## Roadmap

- **More agent state markers** — per-state detection for Codex / opencode /
  others (today they get a presence-only badge).
- **Cross-platform notifications** — Linux (`notify-send`) support; today
  notifications use macOS `osascript`.

## License

MIT — see [LICENSE](LICENSE).
