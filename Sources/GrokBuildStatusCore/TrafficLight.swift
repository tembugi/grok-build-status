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

    public var menuLabel: String {
        switch self {
        case .inactive: "Not running"
        case .idle: "Idle"
        case .completed: "Done"
        case .running: "Running"
        case .waitingForInput: "Waiting"
        }
    }

    public func combining(_ other: TrafficLight) -> TrafficLight {
        self.rawValue >= other.rawValue ? self : other
    }

    /// Compact roster line such as `2 running · 1 waiting`.
    public static func countSummary(_ lights: [TrafficLight]) -> String? {
        var waiting = 0
        var running = 0
        var done = 0
        var idle = 0
        for light in lights {
            switch light {
            case .waitingForInput: waiting += 1
            case .running: running += 1
            case .completed: done += 1
            case .idle: idle += 1
            case .inactive: break
            }
        }
        var parts: [String] = []
        func add(_ count: Int, _ word: String) {
            guard count > 0 else { return }
            parts.append("\(count) \(word)")
        }
        add(waiting, "waiting")
        add(running, "running")
        add(done, "done")
        add(idle, "idle")
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
