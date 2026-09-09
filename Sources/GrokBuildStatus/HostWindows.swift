import AppKit
import GrokBuildStatusCore

/// Live Terminal / iTerm windows and the TTYs of their tabs.
@MainActor
enum HostWindows {
    private static var cache: (at: TimeInterval, windows: [HostWindow])?

    private static let terminalRosterScript = NSAppleScript(source: """
        tell application "Terminal"
            set out to ""
            repeat with w in windows
                set out to out & "W|" & (id of w as text) & linefeed
                repeat with t in tabs of w
                    set tabTTY to ""
                    try
                        set tabTTY to (tty of t as text)
                    end try
                    if tabTTY is not "" then
                        set out to out & "T|" & tabTTY & linefeed
                    end if
                end repeat
            end repeat
            return out
        end tell
        """)

    private static let itermRosterScript = NSAppleScript(source: """
        tell application "iTerm"
            set out to ""
            repeat with w in windows
                set out to out & "W|" & (id of w as text) & linefeed
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionTTY to ""
                        try
                            set sessionTTY to (tty of s as text)
                        end try
                        if sessionTTY is not "" then
                            set out to out & "T|" & sessionTTY & linefeed
                        end if
                    end repeat
                end repeat
            end repeat
            return out
        end tell
        """)

    static func list(force: Bool = false) -> [HostWindow] {
        let now = CFAbsoluteTimeGetCurrent()
        if !force, let cache, now - cache.at < 0.5 {
            return cache.windows
        }
        let windows = fetch()
        cache = (now, windows)
        return windows
    }

    private static func fetch() -> [HostWindow] {
        var windows: [HostWindow] = []
        if isRunning(.terminal), let text = AppleScript.string(from: terminalRosterScript) {
            windows.append(contentsOf: parse(text, app: .terminal))
        }
        if isRunning(.iTerm), let text = AppleScript.string(from: itermRosterScript) {
            windows.append(contentsOf: parse(text, app: .iTerm))
        }
        return windows
    }

    private static func isRunning(_ app: HostApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundleID }
    }

    private static func parse(_ text: String, app: HostApp) -> [HostWindow] {
        HostWindowRoster.parse(text).map { draft in
            HostWindow(id: "\(app.bundleID):\(draft.scriptID)", title: app.title, ttys: draft.ttys)
        }
    }
}
