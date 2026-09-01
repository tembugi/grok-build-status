public enum TrafficLight: Int, Sendable, Equatable {
    /// No live Grok Build session.
    case inactive = 0
    /// Session is open, no turn has finished yet.
    case idle = 1
    /// Session is idle after a finished turn.
    case completed = 2
    /// A turn is running.
    case running = 3
    /// Blocked on the user (permission or question).
    case waitingForInput = 4

    public var name: String {
        switch self {
        case .inactive: "inactive"
        case .idle: "idle"
        case .completed: "done"
        case .running: "running"
        case .waitingForInput: "waiting"
        }
    }

    public var tooltip: String {
        switch self {
        case .inactive: "Grok is not running"
        case .idle: "Grok is idle"
        case .completed: "Grok is done"
        case .running: "Grok is running"
        case .waitingForInput: "Grok is waiting for input"
        }
    }

    public func combining(_ other: TrafficLight) -> TrafficLight {
        self.rawValue >= other.rawValue ? self : other
    }
}
