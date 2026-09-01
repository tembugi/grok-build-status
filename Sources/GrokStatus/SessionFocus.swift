import AppKit
import ApplicationServices
import GrokStatusCore

@MainActor
enum SessionFocus {
    private static var liveCache: (at: TimeInterval, sessions: [ActiveSession])?
    private static var focusCache: (pid: pid_t, at: TimeInterval, value: Bool)?

    static func isGrokSessionFocused() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let frontPID = front.processIdentifier
        let now = CFAbsoluteTimeGetCurrent()
        if let focusCache, focusCache.pid == frontPID, now - focusCache.at < 0.12 {
            return focusCache.value
        }
        let value = liveSessions().contains { ProcessLiveness.isDescendant($0.pid, of: frontPID) }
        focusCache = (frontPID, now, value)
        return value
    }

    static func hasLiveSession() -> Bool {
        !liveSessions().isEmpty
    }

    /// Raises the host window of the most urgent live Grok session.
    @discardableResult
    static func bringSessionToFront() async -> Bool {
        guard let session = preferredLiveSession() else { return false }
        guard let app = hostApplication(for: session.pid) else { return false }

        if app.isHidden {
            app.unhide()
        }

        if let tty = ProcessLiveness.ttyName(of: session.pid),
           let bundleID = app.bundleIdentifier
        {
            activateTTYHost(bundleID: bundleID, tty: tty)
        }

        await orderFront(app, cwd: session.cwd)
        return true
    }

    private static func liveSessions() -> [ActiveSession] {
        let now = CFAbsoluteTimeGetCurrent()
        if let liveCache, now - liveCache.at < 0.2 {
            return liveCache.sessions
        }
        let home = GrokPaths.home()
        guard let loaded = ActiveSessions.load(from: GrokPaths.activeSessions(home: home)) else {
            return liveCache?.sessions ?? []
        }
        let live = loaded.filter { ProcessLiveness.isAlive($0.pid) }
        liveCache = (now, live)
        return live
    }

    /// Terminal hosts that can raise a tab by TTY. Add bundle IDs here.
    private static func activateTTYHost(bundleID: String, tty: String) {
        switch bundleID {
        case "com.apple.Terminal":
            _ = activateTerminalTab(tty: tty)
        case "com.googlecode.iterm2":
            _ = activateITermSession(tty: tty)
        default:
            break
        }
    }

    private static func preferredLiveSession() -> ActiveSession? {
        let home = GrokPaths.home()
        return liveSessions().max { a, b in
            light(for: a, home: home).rawValue < light(for: b, home: home).rawValue
        }
    }

    private static func light(for session: ActiveSession, home: URL) -> TrafficLight {
        let reader = EventFileReader()
        reader.readNew(from: GrokPaths.eventsFile(home: home, cwd: session.cwd, sessionId: session.sessionId))
        return reader.state.light
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

    private static func orderFront(_ app: NSRunningApplication, cwd: String) async {
        NSApp.yieldActivation(to: app)
        carbonSetFront(pid: app.processIdentifier)

        if let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
        }

        _ = app.activate(from: NSRunningApplication.current, options: [.activateAllWindows])
        axRaise(app, cwd: cwd)
    }

    /// HIServices SetFrontProcessWithOptions is unavailable in Swift; call it by symbol.
    private static func carbonSetFront(pid: pid_t) {
        guard let getSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID"),
              let setSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SetFrontProcessWithOptions")
        else { return }
        typealias GetFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
        typealias SetFn = @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32) -> Int32
        let getFn = unsafeBitCast(getSym, to: GetFn.self)
        let setFn = unsafeBitCast(setSym, to: SetFn.self)
        var psn = ProcessSerialNumber()
        guard getFn(pid, &psn) == 0 else { return }
        _ = setFn(&psn, 1 << 1) // kSetFrontProcessCausedByUser
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

    private static func activateTerminalTab(tty: String) -> Bool {
        guard let tty = sanitizedTTY(tty) else { return false }
        return runAppleScript(
            """
            tell application "Terminal"
                set found to false
                repeat with w in windows
                    repeat with t in tabs of w
                        if (tty of t as text) contains "\(tty)" then
                            try
                                set miniaturized of w to false
                            end try
                            set selected tab of w to t
                            set index of w to 1
                            try
                                set frontmost of w to true
                            end try
                            set found to true
                            exit repeat
                        end if
                    end repeat
                    if found then exit repeat
                end repeat
                activate
            end tell
            """
        )
    }

    private static func activateITermSession(tty: String) -> Bool {
        guard let tty = sanitizedTTY(tty) else { return false }
        return runAppleScript(
            """
            tell application "iTerm"
                set found to false
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (tty of s as text) contains "\(tty)" then
                                select w
                                select t
                                select s
                                set found to true
                                exit repeat
                            end if
                        end repeat
                        if found then exit repeat
                    end repeat
                    if found then exit repeat
                end repeat
                activate
            end tell
            """
        )
    }

    private static func sanitizedTTY(_ name: String) -> String? {
        let trimmed = name.split(separator: "/").last.map(String.init) ?? name
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return nil
        }
        return trimmed
    }

    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            _ = script.executeAndReturnError(&error)
            if error == nil { return true }
        }
        return runOsascript(source)
    }

    private static func runOsascript(_ source: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}
