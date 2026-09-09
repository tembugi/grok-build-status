import Foundation

public struct SessionAlert: Equatable, Sendable {
    public var sessionId: String
    public var title: String
    public var light: TrafficLight

    public init(sessionId: String, title: String, light: TrafficLight) {
        self.sessionId = sessionId
        self.title = title
        self.light = light
    }

    public var body: String {
        switch light {
        case .waitingForInput: "\(title) is waiting for input"
        case .completed: "\(title) is done"
        default: light.tooltip
        }
    }
}

public enum SessionAlerts {
    /// Waiting or done that just became so, and that tab is not already selected.
    public static func arriving(
        previous: [String: TrafficLight],
        sessions: [LiveSession],
        seenIDs: Set<String>
    ) -> [SessionAlert] {
        sessions.compactMap { row in
            switch row.light {
            case .waitingForInput, .completed:
                break
            default:
                return nil
            }
            let id = row.session.sessionId
            guard previous[id] != row.light else { return nil }
            guard !seenIDs.contains(id) else { return nil }
            return SessionAlert(sessionId: id, title: row.title, light: row.light)
        }
    }
}

public enum AttentionFocus {
    /// Pulse/bounce may rest only after every session in the combined state
    /// has been selected as a tab. Window focus does not count.
    public static func isSettled(
        light: TrafficLight,
        sessions: [LiveSession],
        seenIDs: Set<String>
    ) -> Bool {
        switch light {
        case .waitingForInput, .completed:
            break
        default:
            return false
        }
        let needy = sessions.filter { $0.light == light }
        guard !needy.isEmpty else { return false }
        return needy.allSatisfy { seenIDs.contains($0.session.sessionId) }
    }
}
