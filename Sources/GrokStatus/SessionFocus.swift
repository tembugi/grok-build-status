import AppKit
import ApplicationServices
import GrokStatusCore

@MainActor
enum SessionFocus {
    private static var tabTTYCache: (pid: pid_t, at: TimeInterval, tty: String?)?

    /// TTY of the selected Terminal/iTerm tab, or nil if unknown.
    /// Never infers this from “Terminal is frontmost.”
    static func selectedTabTTY() -> String? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let frontPID = front.processIdentifier
        let now = CFAbsoluteTimeGetCurrent()
        if let tabTTYCache, tabTTYCache.pid == frontPID, now - tabTTYCache.at < 0.1 {
            return tabTTYCache.tty
        }
        let tty: String?
        switch front.bundleIdentifier {
        case "com.apple.Terminal":
            tty = ProcessLiveness.normalizedTTY(appleScriptText(
                """
                tell application "Terminal"
                    if (count of windows) is 0 then return ""
                    try
                        repeat with w in windows
                            if frontmost of w then
                                return (tty of selected tab of w) as text
                            end if
                        end repeat
                        return (tty of selected tab of window 1) as text
                    end try
                    return ""
                end tell
                """
            ))
        case "com.googlecode.iterm2":
            tty = ProcessLiveness.normalizedTTY(appleScriptText(
                """
                tell application "iTerm"
                    if (count of windows) is 0 then return ""
                    try
                        return (tty of current session of current tab of current window) as text
                    end try
                    return ""
                end tell
                """
            ))
        default:
            tty = nil
        }
        tabTTYCache = (frontPID, now, tty)
        return tty
    }

    /// Raises the host window / terminal tab of the given live Grok session.
    @discardableResult
    static func bringSessionToFront(_ session: ActiveSession) -> Bool {
        guard let app = hostApplication(for: session.pid) else { return false }

        if app.isHidden {
            app.unhide()
        }

        NSApp.yieldActivation(to: app)

        let tty = ProcessLiveness.ttyName(of: session.pid)
        let folder = URL(fileURLWithPath: session.cwd).lastPathComponent
        let alreadyFront = NSWorkspace.shared.frontmostApplication?.processIdentifier
            == app.processIdentifier
        var selectedTab = false
        if let bundleID = app.bundleIdentifier {
            selectedTab = activateTTYHost(
                bundleID: bundleID,
                tty: tty,
                folder: folder,
                bringForward: !alreadyFront
            )
        }

        if !selectedTab {
            axRaise(app, cwd: session.cwd)
        }
        return true
    }

    private static func activateTTYHost(
        bundleID: String,
        tty: String?,
        folder: String,
        bringForward: Bool
    ) -> Bool {
        switch bundleID {
        case "com.apple.Terminal":
            return activateTerminalTab(tty: tty, folder: folder, bringForward: bringForward)
        case "com.googlecode.iterm2":
            return activateITermSession(tty: tty, folder: folder, bringForward: bringForward)
        default:
            return false
        }
    }

    private static func scriptLiteral(_ raw: String) -> String {
        "\""
            + raw.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }

    private static func scriptSucceeded(_ source: String) -> Bool {
        let text = appleScriptText(source)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return text == "true"
    }

    private static func hostApplication(for pid: pid_t) -> NSRunningApplication? {
        var current = pid
        var fallback: NSRunningApplication?
        for _ in 0..<24 {
            if let app = NSRunningApplication(processIdentifier: current),
               app.activationPolicy != .prohibited,
               app.bundleIdentifier != Bundle.main.bundleIdentifier
            {
                if app.activationPolicy == .regular {
                    return app
                }
                fallback = app
            }
            guard let parent = ProcessLiveness.parent(of: current), parent != current, parent > 1 else {
                return fallback
            }
            current = parent
        }
        return fallback
    }

    private static func axRaise(_ app: NSRunningApplication, cwd: String) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXWindowsAttribute as CFString,
            &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            return
        }

        let needle = URL(fileURLWithPath: cwd).lastPathComponent
        let match = windows.first { window in
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? ""
            return !needle.isEmpty && title.localizedCaseInsensitiveContains(needle)
        } ?? windows[0]

        AXUIElementPerformAction(match, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(match, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(match, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private static func activateTerminalTab(tty: String?, folder: String, bringForward: Bool) -> Bool {
        let ttyNeedle = sanitizedTTY(tty ?? "") ?? ""
        let titleNeedle = folder
        guard !ttyNeedle.isEmpty || !titleNeedle.isEmpty else { return false }
        let activateLine = bringForward ? "activate" : ""
        return scriptSucceeded(
            """
            tell application "Terminal"
                repeat with wi from 1 to (count of windows)
                    set w to window wi
                    repeat with ti from 1 to (count of tabs of w)
                        set t to tab ti of w
                        set tabTTY to ""
                        set tabTitle to ""
                        try
                            set tabTTY to (tty of t as text)
                        end try
                        try
                            set tabTitle to (custom title of t as text)
                        end try
                        try
                            set tabTitle to tabTitle & (title of t as text)
                        end try
                        if ("\(ttyNeedle)" is not "" and tabTTY contains "\(ttyNeedle)") or ("\(titleNeedle)" is not "" and tabTitle contains \(scriptLiteral(titleNeedle))) then
                            try
                                set miniaturized of w to false
                            end try
                            try
                                set visible of w to true
                            end try
                            set selected tab of w to t
                            try
                                set selected of t to true
                            end try
                            set index of w to 1
                            try
                                set frontmost of w to true
                            end try
                            \(activateLine)
                            return "true"
                        end if
                    end repeat
                end repeat
                return "false"
            end tell
            """
        )
    }

    private static func activateITermSession(tty: String?, folder: String, bringForward: Bool) -> Bool {
        let ttyNeedle = sanitizedTTY(tty ?? "") ?? ""
        let titleNeedle = folder
        guard !ttyNeedle.isEmpty || !titleNeedle.isEmpty else { return false }
        let activateLine = bringForward ? "activate" : ""
        return scriptSucceeded(
            """
            tell application "iTerm"
                repeat with wi from 1 to (count of windows)
                    set w to window wi
                    repeat with ti from 1 to (count of tabs of w)
                        set t to tab ti of w
                        repeat with si from 1 to (count of sessions of t)
                            set s to session si of t
                            set sessionTTY to ""
                            set sessionName to ""
                            try
                                set sessionTTY to (tty of s as text)
                            end try
                            try
                                set sessionName to (name of s as text)
                            end try
                            if ("\(ttyNeedle)" is not "" and sessionTTY contains "\(ttyNeedle)") or ("\(titleNeedle)" is not "" and sessionName contains \(scriptLiteral(titleNeedle))) then
                                select w
                                select t
                                select s
                                \(activateLine)
                                return "true"
                            end if
                        end repeat
                    end repeat
                end repeat
                return "false"
            end tell
            """
        )
    }

    private static func sanitizedTTY(_ name: String) -> String? {
        ProcessLiveness.normalizedTTY(name)
    }

    private static func appleScriptText(_ source: String) -> String? {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let result = script.executeAndReturnError(&error)
            if error == nil, let text = result.stringValue, !text.isEmpty {
                return text
            }
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
