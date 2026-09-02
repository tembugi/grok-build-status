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

    public static func normalizedTTY(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.split(separator: "/").last.map(String.init) ?? name
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return nil
        }
        return trimmed
    }

    /// Controlling TTY name such as `ttys000`, or `nil` if the process has none.
    public static func ttyName(of pid: pid_t) -> String? {
        if let name = sysctlTTY(of: pid) { return name }
        return psTTY(of: pid)
    }

    private static func sysctlTTY(of pid: pid_t) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let dev = info.kp_eproc.e_tdev
        guard dev != 0, dev != -1 else { return nil }
        var buf = [CChar](repeating: 0, count: 128)
        let ok = buf.withUnsafeMutableBufferPointer { ptr in
            devname_r(dev, S_IFCHR, ptr.baseAddress, Int32(ptr.count)) != nil
        }
        guard ok else { return nil }
        let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return normalizedTTY(String(decoding: bytes, as: UTF8.self))
    }

    private static func psTTY(of pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-p", "\(pid)", "-o", "tty="]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return normalizedTTY(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return nil
        }
    }
}
