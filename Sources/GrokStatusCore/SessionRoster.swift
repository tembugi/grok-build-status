import Foundation

public struct SessionState: Equatable, Sendable {
    public var session: ActiveSession
    public var light: TrafficLight

    public init(session: ActiveSession, light: TrafficLight) {
        self.session = session
        self.light = light
    }
}

public struct LiveSession: Equatable, Sendable {
    public var session: ActiveSession
    public var light: TrafficLight
    public var title: String

    public init(session: ActiveSession, light: TrafficLight, title: String) {
        self.session = session
        self.light = light
        self.title = title
    }

    public var menuTitle: String {
        "\(title) — \(light.menuLabel)"
    }
}

public enum SessionRoster {
    public static func snapshots(
        of sessions: [ActiveSession],
        home: URL
    ) -> [LiveSession] {
        labeled(
            sessions.map { session in
                SessionState(session: session, light: light(for: session, home: home))
            },
            home: home
        )
    }

    /// Folder titles only. Does not read `events.jsonl`.
    public static func labeled(_ states: [SessionState], home: URL) -> [LiveSession] {
        let rows = states.map { state in
            LiveSession(
                session: state.session,
                light: state.light,
                title: folderName(of: state.session.cwd)
            )
        }
        return disambiguate(rows, home: home).sorted { lhs, rhs in
            if lhs.light.rawValue != rhs.light.rawValue {
                return lhs.light.rawValue > rhs.light.rawValue
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func light(for session: ActiveSession, home: URL) -> TrafficLight {
        let reader = EventFileReader()
        reader.readNew(
            from: GrokPaths.eventsFile(home: home, cwd: session.cwd, sessionId: session.sessionId)
        )
        return reader.state.light
    }

    private static func folderName(of cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    private static func disambiguate(_ rows: [LiveSession], home: URL) -> [LiveSession] {
        var counts: [String: Int] = [:]
        for row in rows {
            counts[row.session.cwd, default: 0] += 1
        }
        return rows.map { row in
            guard counts[row.session.cwd, default: 0] > 1 else { return row }
            var copy = row
            if let generated = generatedTitle(for: row.session, home: home) {
                copy.title = "\(row.title) — \(truncate(generated, 28))"
            } else {
                copy.title = "\(row.title) — \(shortID(row.session.sessionId))"
            }
            return copy
        }
    }

    private static func generatedTitle(for session: ActiveSession, home: URL) -> String? {
        let url = GrokPaths.summaryFile(home: home, cwd: session.cwd, sessionId: session.sessionId)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let title = (object["generated_title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { return nil }
        return title
    }

    private static func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }

    private static func truncate(_ text: String, _ max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max - 1)) + "…"
    }
}
