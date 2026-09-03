import Foundation

public struct EventLine: Equatable, Sendable {
    public var type: String
    public var phase: String?
    public var toolName: String?

    public init(type: String, phase: String? = nil, toolName: String? = nil) {
        self.type = type
        self.phase = phase
        self.toolName = toolName
    }

    public static func parse(_ line: String) -> EventLine? {
        parse(line.data(using: .utf8) ?? Data())
    }

    public static func parse(_ data: Data) -> EventLine? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let type = object["type"] as? String else { return nil }
        return EventLine(
            type: type,
            phase: object["phase"] as? String,
            toolName: object["tool_name"] as? String
        )
    }
}

public struct SessionRuntimeState: Equatable, Sendable {
    public var turnOpen = false
    public var completedTurn = false
    public var phase: String?
    public var openAskTools = 0
    public var permissionOutstanding = false

    public init() {}

    public mutating func apply(_ event: EventLine) {
        switch event.type {
        case "turn_started":
            turnOpen = true
            completedTurn = false
        case "turn_ended":
            turnOpen = false
            completedTurn = true
            phase = nil
            openAskTools = 0
            permissionOutstanding = false
        case "phase_changed":
            phase = event.phase
        case "permission_requested":
            permissionOutstanding = true
        case "permission_resolved":
            permissionOutstanding = false
        case "tool_started":
            if event.toolName == "ask_user_question" {
                openAskTools += 1
            }
        case "tool_completed":
            if event.toolName == "ask_user_question" {
                openAskTools = max(0, openAskTools - 1)
            }
        default:
            break
        }
    }

    public var light: TrafficLight {
        if permissionOutstanding || phase == "permission_prompt" || openAskTools > 0 {
            return .waitingForInput
        }
        if turnOpen {
            return .running
        }
        if completedTurn {
            return .completed
        }
        return .idle
    }
}
