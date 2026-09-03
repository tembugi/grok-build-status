# Grok Build Status

See **Grok Build**'s status from the Mac menu bar.

- Animated to tell at a glance if a session is idle, running, waiting for you, or done
- Get a Mac notification when Grok is waiting or done
- Jump to a live session from the menu
- Check weekly usage

Unofficial. Not affiliated with SpaceXAI. Built with Grok Build.

## How to use

Download [GrokBuildStatus.dmg](https://github.com/tembugi/grok-build-status/releases/latest). Open it and drag **Grok Build Status** onto Applications. Apple Silicon, macOS 14+.

First launch may be blocked. Right-click the app, choose Open, then Open again.

Click the menu bar icon for live sessions, weekly usage, Notifications, and Start on login. Click a session to jump to it. macOS may ask to let Grok Build Status control Terminal or iTerm.

Notifications are on by default. macOS will ask for permission the first time one would appear, or when you turn the switch on. Click a notification to jump to that session. Turn **Notifications** off in the menu if you do not want them.

Start on login only works after the app is in Applications.

Drag the app to the Trash to remove it. Login is cleared automatically.

## Feedback

[Open an issue](https://github.com/tembugi/grok-build-status/issues).

## Privacy

Grok Build Status stays on your Mac. It does not open a network connection and does not send telemetry.

It reads Grok Build's local files under `~/.grok` so it can draw the icon and menu:

- `active_sessions.json` — which sessions are live
- `sessions/.../events.jsonl` — running / waiting / done
- `sessions/.../summary.json` — title when two sessions share a folder
- `logs/unified.jsonl` — latest billing line for weekly usage

It does not upload those files. Jumping to a session talks to Terminal or iTerm on this Mac only.

## From source

Swift 6.2 (Xcode or Command Line Tools) on Apple Silicon, macOS 14+.

```
swift test
./package.sh
```

`./package.sh` runs tests, then writes `dist/GrokBuildStatus.dmg`.

`GrokBuildStatus --print` writes the current combined status (`inactive`, `idle`, `running`, `waiting`, `done`) and exits.

Layout: `GrokBuildStatusCore` reads `~/.grok` and has no UI. `GrokBuildStatus` is the menu bar extra (`SessionStore` watches the files, `StatusItemController` draws the icon and menu). The icon animates only while a session is running, or waiting/done on a tab you have not selected, and sleeps when the extra is hidden.

## License

[CC0](LICENSE) for this project's original source. Grok names and the official Grok icon belong to SpaceXAI.
