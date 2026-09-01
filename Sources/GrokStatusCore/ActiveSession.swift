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

    public static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }

    public static func isDescendant(_ pid: pid_t, of ancestor: pid_t) -> Bool {
        var current = pid
        for _ in 0..<24 {
            if current == ancestor { return true }
            guard let parent = parent(of: current), parent != current else { return false }
            current = parent
            if current <= 1 { return false }
        }
        return false
    }
}
