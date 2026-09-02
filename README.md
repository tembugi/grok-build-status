# Grok Status

Unofficial macOS menu extra for **Grok Build**. It sits in the menu bar and shows whether a session is idle, running, waiting for you, or done.

You already need Grok Build. This app only reads `~/.grok`. It does not start sessions or talk to Grok.

Not affiliated with SpaceXAI.

## Install

Mac with Apple Silicon, macOS 14 or later.

**Just the app** — download [GrokStatus.dmg](https://github.com/tembugi/grok-build-status/releases/latest) from the latest GitHub Release, open it, and drag **Grok Status** onto Applications. No source or compiling.

The first launch may be blocked as an unidentified developer. Right-click the app, choose Open, then Open again.

**From source** (after you change the code). Needs the Swift toolchain (Xcode or Command Line Tools):

1. `./package.sh`
2. Open `dist/GrokStatus.dmg`
3. Drag **Grok Status** onto Applications

To start at login, open the menu extra and turn on **Start on login** (only after the app is in Applications).

To remove it, drag the app to the Trash. Start on login is cleared automatically.

## Menu

- Header such as `1 running` or `2 running · 1 waiting` (`None` if Grok Build is not running)
- One row per live session — idle / running / waiting / done. Click to focus that terminal (Terminal and iTerm)
- Weekly usage, after Grok Build has fetched billing
- **Start on login**
- Quit

The icon orbits while a turn is running, bounces when Grok is waiting for a permission or a question, and pulses when a turn is done.

## How it works

Reads `~/.grok` (or `GROK_HOME`):

- `active_sessions.json` — live sessions
- `sessions/…/events.jsonl` — turn state
- `sessions/…/summary.json` — title, when two sessions share a folder
- `logs/unified.jsonl` — weekly usage

## License

[CC0](LICENSE), except the official Grok icon, which belongs to SpaceXAI.
