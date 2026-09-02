# Grok Status

See **Grok Build**'s status from the Mac menu bar.

- Animated to tell at a glance if a session is idle, running, waiting for you, or done
- Get a Mac notification when Grok is waiting or done
- Jump to a live session from the menu
- Check weekly usage

Unofficial. Not affiliated with SpaceXAI.

## How to use

Download [GrokStatus.dmg](https://github.com/tembugi/grok-build-status/releases/latest). Open it and drag **GrokStatus** onto Applications. Apple Silicon, macOS 14+.

First launch may be blocked. Right-click the app, choose Open, then Open again.

Click the menu bar icon for live sessions, weekly usage, Notifications, and Start on login. Click a session to jump to it.

Notifications are on by default. macOS will ask for permission the first time one would appear, or when you turn the switch on. Click a notification to jump to that session. Turn **Notifications** off in the menu if you do not want them.

Start on login only works after the app is in Applications.

Drag the app to the Trash to remove it. Login is cleared automatically.

From source: Swift toolchain (Xcode or Command Line Tools), then `./package.sh` and open `dist/GrokStatus.dmg`.

## License

[CC0](LICENSE) for this project's original source. Grok names and the official Grok icon belong to SpaceXAI.
