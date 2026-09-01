import Foundation

public enum GrokPaths {
    public static func home(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["GROK_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    }

    public static func activeSessions(home: URL) -> URL {
        home.appendingPathComponent("active_sessions.json")
    }

    public static func unifiedLog(home: URL) -> URL {
        home.appendingPathComponent("logs").appendingPathComponent("unified.jsonl")
    }

    public static func eventsFile(home: URL, cwd: String, sessionId: String) -> URL {
        home
            .appendingPathComponent("sessions")
            .appendingPathComponent(encodeCwd(cwd))
            .appendingPathComponent(sessionId)
            .appendingPathComponent("events.jsonl")
    }

    /// Matches Grok's session-group folder names (`urllib.parse.quote(cwd, safe="")`).
    public static func encodeCwd(_ cwd: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return cwd.addingPercentEncoding(withAllowedCharacters: allowed) ?? cwd
    }
}
