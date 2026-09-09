import Foundation

/// A Terminal / iTerm window that can own multiple live sessions as tabs.
public struct HostWindow: Equatable, Sendable {
    public var id: String
    public var title: String
    public var ttys: Set<String>

    public init(id: String, title: String, ttys: Set<String>) {
        self.id = id
        self.title = title
        self.ttys = ttys
    }
}

/// Live sessions that share a host window.
public struct SessionGroup: Equatable, Sendable {
    public var id: String
    public var title: String
    public var sessions: [LiveSession]

    public init(id: String, title: String, sessions: [LiveSession]) {
        self.id = id
        self.title = title
        self.sessions = sessions
    }

    public static func fallbackID(sessionID: String) -> String {
        "session:\(sessionID)"
    }
}

public enum HostWindowRoster {
    public struct Window: Equatable, Sendable {
        public var scriptID: String
        public var ttys: Set<String>

        public init(scriptID: String, ttys: Set<String>) {
            self.scriptID = scriptID
            self.ttys = ttys
        }
    }

    /// Parses the `W|id|…` / `T|tty` roster from Terminal or iTerm.
    public static func parse(_ text: String) -> [Window] {
        var drafts: [Window] = []
        var scriptID: String?
        var ttys: Set<String> = []

        func flush() {
            guard let scriptID, !ttys.isEmpty else { return }
            drafts.append(Window(scriptID: scriptID, ttys: ttys))
        }

        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let kind = parts.first else { continue }
            if kind == "W" {
                flush()
                ttys = []
                scriptID = parts.count > 1 ? parts[1] : nil
            } else if kind == "T", parts.count > 1, let tty = ProcessLiveness.normalizedTTY(parts[1]) {
                ttys.insert(tty)
            }
        }
        flush()
        return drafts
    }
}

public enum SessionGroups {
    /// Groups sessions by the host window that owns their TTY.
    /// Sessions whose TTY is not in any window become their own group.
    /// Group order follows the first session of each group in `sessions`.
    public static func make(
        sessions: [LiveSession],
        windows: [HostWindow],
        ttys: [pid_t: String]
    ) -> [SessionGroup] {
        var ttyToWindow: [String: String] = [:]
        var titles: [String: String] = [:]
        ttyToWindow.reserveCapacity(windows.reduce(0) { $0 + $1.ttys.count })
        for window in windows {
            titles[window.id] = window.title
            for tty in window.ttys {
                ttyToWindow[tty] = window.id
            }
        }

        var grouped: [String: [LiveSession]] = [:]
        var order: [String] = []
        for row in sessions {
            let groupID: String
            if let tty = ttys[row.session.pid], let windowID = ttyToWindow[tty] {
                groupID = windowID
            } else {
                groupID = SessionGroup.fallbackID(sessionID: row.session.sessionId)
            }
            if grouped[groupID] == nil {
                order.append(groupID)
            }
            grouped[groupID, default: []].append(row)
        }
        let groups = order.map { id in
            SessionGroup(
                id: id,
                title: titles[id] ?? "Window",
                sessions: grouped[id] ?? []
            )
        }
        return numbered(groups)
    }

    /// `Terminal 1`, `Terminal 2` in list order, separately per host name.
    public static func numbered(_ groups: [SessionGroup]) -> [SessionGroup] {
        var counts: [String: Int] = [:]
        return groups.map { group in
            var copy = group
            let n = counts[group.title, default: 0] + 1
            counts[group.title] = n
            copy.title = "\(group.title) \(n)"
            return copy
        }
    }
}
