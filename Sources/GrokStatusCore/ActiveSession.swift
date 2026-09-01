import Darwin
import Foundation

public struct ActiveSession: Decodable, Sendable, Equatable {
    public var sessionId: String
    public var pid: pid_t
    public var cwd: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case pid
        case cwd
    }

    public init(sessionId: String, pid: pid_t, cwd: String) {
        self.sessionId = sessionId
        self.pid = pid
        self.cwd = cwd
    }
}

public enum ActiveSessions {
    /// `nil` means the file existed but was not valid JSON (likely a mid-write).
    public static func load(from url: URL) -> [ActiveSession]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.isEmpty { return [] }
        return try? JSONDecoder().decode([ActiveSession].self, from: data)
    }
}

public enum ProcessLiveness {
    public static func isAlive(_ pid: pid_t) -> Bool {
        if pid <= 0 { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
