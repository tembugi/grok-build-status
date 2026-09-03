import Foundation

public struct StatusEvaluator: Sendable {
    public var isProcessAlive: @Sendable (pid_t) -> Bool

    public init(isProcessAlive: @escaping @Sendable (pid_t) -> Bool = ProcessLiveness.isAlive) {
        self.isProcessAlive = isProcessAlive
    }

    public func evaluate(home: URL) -> TrafficLight {
        guard let sessions = ActiveSessions.load(from: GrokPaths.activeSessions(home: home)) else {
            return .inactive
        }
        var light = TrafficLight.inactive
        for session in sessions where isProcessAlive(session.pid) {
            let reader = EventFileReader()
            reader.readNew(from: GrokPaths.eventsFile(home: home, cwd: session.cwd, sessionId: session.sessionId))
            light = light.combining(reader.state.light)
        }
        return light
    }
}
