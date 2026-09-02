# Grok Status

Unofficial macOS menu extra for Grok Build. It sits in the menu bar and shows whether a session is idle, running, waiting for you, or done.

Not affiliated with SpaceXAI.

## Install

Mac with Apple Silicon, macOS 14 or later.

**Just the app** — download [Grok Status.dmg](https://github.com/tembugi/grok-build-status/releases/latest) from the latest GitHub Release, open it, and drag **Grok Status** onto Applications. No source or compiling.

The first launch may be blocked as an unidentified developer. Right-click the app, choose Open, then Open again.

**From source** (after you change the code):

1. `./package.sh`
2. Open `dist/Grok Status.dmg`
3. Drag **Grok Status** onto Applications

To start at login, open the menu extra and turn on **Start on login** (only after the app is in Applications).

To remove it, drag the app to the Trash. Start on login is cleared automatically.

## Menu

- Live sessions — each row shows idle / running / waiting / done; click to focus that terminal (Terminal and iTerm). With more than one session, a line like `2 running · 1 waiting` sits above the list.
- Weekly usage, when Grok has fetched billing
- **Start on login**
- Quit

The icon animates while a turn is running.

## How it works

Reads `~/.grok` (or `GROK_HOME`):

- `active_sessions.json` — live sessions
- `sessions/…/events.jsonl` — turn state
- `sessions/…/summary.json` — title, when two sessions share a folder
- `logs/unified.jsonl` — weekly usage

## License

[CC0](LICENSE), except the official Grok icon, which belongs to SpaceXAI.
