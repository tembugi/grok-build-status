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

public struct SessionSnapshot: Equatable, Sendable {
    public var light: TrafficLight
    public var sessions: [LiveSession]
    public var usage: WeeklyUsage?

    public static let empty = SessionSnapshot(light: .inactive, sessions: [], usage: nil)

    public init(light: TrafficLight, sessions: [LiveSession], usage: WeeklyUsage? = nil) {
        self.light = light
        self.sessions = sessions
        self.usage = usage
    }
}
