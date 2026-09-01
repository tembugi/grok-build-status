import AppKit
import GrokStatusCore

enum SessionFocus {
    static func isGrokSessionFocused() -> Bool {
        let home = GrokPaths.home()
        guard let sessions = ActiveSessions.load(from: GrokPaths.activeSessions(home: home)) else {
            return false
        }
        let live = sessions.filter { ProcessLiveness.isAlive($0.pid) }
        guard !live.isEmpty else { return false }
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let frontPID = front.processIdentifier
        return live.contains { ProcessLiveness.isDescendant($0.pid, of: frontPID) }
    }
}
