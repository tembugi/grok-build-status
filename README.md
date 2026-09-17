# Grok Build Status

See **Grok Build**'s status from the Mac menu bar.

- Animated to tell at a glance if a session is idle, running, waiting for you, or done
- Get a Mac notification when Grok is waiting or done
- Jump to a live session from the menu
- Check weekly usage and when the next reset is

Unofficial. Not affiliated with SpaceXAI.

## How to use

Download [GrokBuildStatus.dmg](https://github.com/tembugi/grok-build-status/releases/latest). Open it and drag **Grok Build Status** onto Applications. Apple Silicon, macOS 14+.

First launch may be blocked. Right-click the app, choose Open, then Open again.

Click the menu bar icon to see details. Click a session to jump to it.

Notifications are on by default. macOS will ask for permission the first time one would appear, or when you turn the switch on. Click a notification to jump to that session. Turn **Notifications** off in the menu if you don't want them.

**Start on login** is in the menu. It only works after the app is in Applications.

Drag the app to the Trash to remove it. Login is cleared automatically.

## Feedback

[Open an issue](https://github.com/tembugi/grok-build-status/issues).

## Privacy

Grok Build Status stays on your Mac. It only reads what it needs to function. It does not collect your information or send telemetry.

It asks GitHub for the latest release when you open the menu. Update opens this project's GitHub releases page.

## From source

Built with Grok Build.

Swift 6.2 (Xcode or Command Line Tools) on Apple Silicon, macOS 14+.

```
swift test
./package.sh
```

`./package.sh` runs tests, then writes `dist/GrokBuildStatus.dmg`.

## License

[CC0](LICENSE) for this project's original source. Grok names and the official Grok icon belong to SpaceXAI.
