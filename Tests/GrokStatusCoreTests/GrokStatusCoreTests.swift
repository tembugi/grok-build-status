import Foundation
import Testing
@testable import GrokStatusCore

struct SessionRuntimeStateTests {
    @Test func idleByDefault() {
        #expect(SessionRuntimeState().light == .idle)
    }

    @Test func turnStartedIsRunning() {
        var state = SessionRuntimeState()
        state.apply(EventLine(type: "turn_started"))
        #expect(state.light == .running)
    }

    @Test func turnEndedIsCompleted() {
        var state = SessionRuntimeState()
        state.apply(EventLine(type: "turn_started"))
        state.apply(EventLine(type: "phase_changed", phase: "streaming_text"))
        state.apply(EventLine(type: "turn_ended"))
        #expect(state.light == .completed)
    }

    @Test func nextTurnClearsCompleted() {
        var state = SessionRuntimeState()
        state.apply(EventLine(type: "turn_started"))
        state.apply(EventLine(type: "turn_ended"))
        #expect(state.light == .completed)
        state.apply(EventLine(type: "turn_started"))
        #expect(state.light == .running)
    }

    @Test func permissionPromptIsWaiting() {
        var state = SessionRuntimeState()
        state.apply(EventLine(type: "turn_started"))
        state.apply(EventLine(type: "phase_changed", phase: "permission_prompt"))
        state.apply(EventLine(type: "permission_requested", toolName: "run_terminal_command"))
        #expect(state.light == .waitingForInput)
    }

    @Test func autoApprovedPermissionReturnsToRunning() {
        var state = SessionRuntimeState()
        state.apply(EventLine(type: "turn_started"))
        state.apply(EventLine(type: "phase_changed", phase: "permission_prompt"))
        state.apply(EventLine(type: "permission_requested", toolName: "read_file"))
        state.apply(EventLine(type: "permission_resolved", toolName: "read_file"))
        state.apply(EventLine(type: "phase_changed", phase: "tool_execution"))
        #expect(state.light == .running)
    }

    @Test func askUserQuestionIsWaitingUntilCompleted() {
        var state = SessionRuntimeState()
        state.apply(EventLine(type: "turn_started"))
        state.apply(EventLine(type: "tool_started", toolName: "ask_user_question"))
        state.apply(EventLine(type: "permission_requested", toolName: "ask_user_question"))
        state.apply(EventLine(type: "permission_resolved", toolName: "ask_user_question"))
        state.apply(EventLine(type: "phase_changed", phase: "tool_execution"))
        #expect(state.light == .waitingForInput)

        state.apply(EventLine(type: "tool_completed", toolName: "ask_user_question"))
        #expect(state.light == .running)
    }

    @Test func combiningPicksHigherPriority() {
        #expect(TrafficLight.running.combining(.waitingForInput) == .waitingForInput)
        #expect(TrafficLight.idle.combining(.running) == .running)
        #expect(TrafficLight.inactive.combining(.idle) == .idle)
        #expect(TrafficLight.completed.combining(.running) == .running)
        #expect(TrafficLight.idle.combining(.completed) == .completed)
    }

    @Test func countSummary() {
        #expect(TrafficLight.countSummary([]) == nil)
        #expect(TrafficLight.countSummary([.inactive]) == nil)
        #expect(TrafficLight.countSummary([.running]) == "1 running")
        #expect(
            TrafficLight.countSummary([.running, .running, .waitingForInput, .completed, .idle])
                == "1 waiting · 2 running · 1 done · 1 idle"
        )
    }
}

struct SessionRosterTests {
    @Test func listsAndSortsLiveSessions() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-status-roster-\(UUID().uuidString)")
        let alpha = "/Users/alex/Projects/alpha"
        let beta = "/Users/alex/Projects/beta"
        defer { try? FileManager.default.removeItem(at: home) }

        try writeSession(
            home: home,
            cwd: alpha,
            id: "session-a",
            events: #"{"type":"turn_started"}\#n{"type":"turn_ended"}\#n"#
        )
        try writeSession(
            home: home,
            cwd: beta,
            id: "session-b",
            events: #"{"type":"turn_started"}\#n{"type":"permission_requested","tool_name":"run_terminal_command"}\#n"#
        )

        let rows = SessionRoster.snapshots(
            of: [
                ActiveSession(sessionId: "session-a", pid: 1, cwd: alpha),
                ActiveSession(sessionId: "session-b", pid: 2, cwd: beta),
            ],
            home: home
        )
        #expect(rows.map(\.title) == ["beta", "alpha"])
        #expect(rows.map(\.light) == [.waitingForInput, .completed])
        #expect(rows[0].menuTitle == "beta — Waiting")
        #expect(rows[1].menuTitle == "alpha — Done")
    }

    @Test func disambiguatesSameFolderWithGeneratedTitle() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-status-roster-dup-\(UUID().uuidString)")
        let cwd = "/Users/alex/Projects/demo"
        defer { try? FileManager.default.removeItem(at: home) }

        try writeSession(home: home, cwd: cwd, id: "session-a", events: "", title: "Fix login")
        try writeSession(home: home, cwd: cwd, id: "session-b", events: "", title: "Write tests")

        let rows = SessionRoster.snapshots(
            of: [
                ActiveSession(sessionId: "session-a", pid: 1, cwd: cwd),
                ActiveSession(sessionId: "session-b", pid: 2, cwd: cwd),
            ],
            home: home
        )
        #expect(rows.map(\.title).sorted() == ["demo — Fix login", "demo — Write tests"])
    }

    private func writeSession(
        home: URL,
        cwd: String,
        id: String,
        events: String,
        title: String? = nil
    ) throws {
        let dir = GrokPaths.sessionDirectory(home: home, cwd: cwd, sessionId: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try events.write(to: GrokPaths.eventsFile(home: home, cwd: cwd, sessionId: id), atomically: true, encoding: .utf8)
        if let title {
            try """
            {"generated_title":"\(title)"}
            """.write(
                to: GrokPaths.summaryFile(home: home, cwd: cwd, sessionId: id),
                atomically: true,
                encoding: .utf8
            )
        }
    }
}

struct GrokPathsTests {
    @Test func encodesCwdLikeGrok() {
        #expect(
            GrokPaths.encodeCwd("/Users/alex/Projects/my app")
                == "%2FUsers%2Falex%2FProjects%2Fmy%20app"
        )
    }
}

struct ProcessLivenessTests {
    @Test func ttyNameOfMissingPidIsNil() {
        #expect(ProcessLiveness.ttyName(of: 0) == nil)
        #expect(ProcessLiveness.ttyName(of: -1) == nil)
    }

    @Test func normalizedTTY() {
        #expect(ProcessLiveness.normalizedTTY("/dev/ttys000") == "ttys000")
        #expect(ProcessLiveness.normalizedTTY("ttys012") == "ttys012")
        #expect(ProcessLiveness.normalizedTTY("") == nil)
        #expect(ProcessLiveness.normalizedTTY("not a tty") == nil)
    }

    @Test func parentOfInitIsNil() {
        #expect(ProcessLiveness.parent(of: 1) == nil || ProcessLiveness.parent(of: 1) == 0)
    }
}

struct EventFileReaderTests {
    @Test func tailsAppendsAndResetsOnTruncate() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("events.jsonl")

        try #"{"type":"turn_started"}\#n"#.write(to: file, atomically: true, encoding: .utf8)
        let reader = EventFileReader()
        reader.readNew(from: file)
        #expect(reader.state.light == .running)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"type":"turn_ended"}\#n"#.utf8))
        try handle.close()
        reader.readNew(from: file)
        #expect(reader.state.light == .completed)

        try #"{"type":"turn_started"}\#n"#.write(to: file, atomically: true, encoding: .utf8)
        reader.readNew(from: file)
        #expect(reader.state.light == .running)
    }

    @Test func missingFileResetsState() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("events.jsonl")

        try #"{"type":"turn_started"}\#n"#.write(to: file, atomically: true, encoding: .utf8)
        let reader = EventFileReader()
        reader.readNew(from: file)
        #expect(reader.state.light == .running)

        try FileManager.default.removeItem(at: file)
        reader.readNew(from: file)
        #expect(reader.state.light == .idle)
        #expect(reader.state.turnOpen == false)
    }

    @Test func rereadDoesNotDoubleCountAskUser() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("events.jsonl")

        try #"{"type":"turn_started"}\#n{"type":"tool_started","tool_name":"ask_user_question"}\#n"#
            .write(to: file, atomically: true, encoding: .utf8)
        let reader = EventFileReader()
        reader.readNew(from: file)
        #expect(reader.state.light == .waitingForInput)
        #expect(reader.state.openAskTools == 1)

        reader.readNew(from: file)
        #expect(reader.state.openAskTools == 1)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"type":"tool_completed","tool_name":"ask_user_question"}\#n"#.utf8))
        try handle.close()
        reader.readNew(from: file)
        #expect(reader.state.openAskTools == 0)
        #expect(reader.state.light == .running)
    }

    @Test func holdsIncompleteLastLine() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("events.jsonl")

        try #"{"type":"turn_started"}"#.write(to: file, atomically: true, encoding: .utf8)
        let reader = EventFileReader()
        reader.readNew(from: file)
        #expect(reader.state.light == .idle)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
        reader.readNew(from: file)
        #expect(reader.state.light == .running)
    }
}

struct ActiveSessionsLoadTests {
    @Test func missingFileIsEmpty() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("active-sessions-missing-\(UUID().uuidString).json")
        let loaded = ActiveSessions.load(from: url)
        #expect(loaded != nil)
        #expect(loaded == [])
    }

    @Test func emptyFileIsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("active-sessions-empty-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)
        let loaded = ActiveSessions.load(from: url)
        #expect(loaded != nil)
        #expect(loaded == [])
    }

    @Test func invalidJSONIsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("active-sessions-bad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try "[".write(to: url, atomically: true, encoding: .utf8)
        #expect(ActiveSessions.load(from: url) == nil)
    }

    @Test func validJSONDecodesAndIgnoresUnknownKeys() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("active-sessions-ok-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [{"session_id":"abc","pid":42,"cwd":"/tmp/demo","opened_at":"2026-09-01T00:00:00Z"}]
        """.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ActiveSessions.load(from: url)
        #expect(loaded == [ActiveSession(sessionId: "abc", pid: 42, cwd: "/tmp/demo")])
    }
}

struct StatusEvaluatorTests {
    @Test func usesLiveSessionEvents() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-status-test-\(UUID().uuidString)")
        let cwd = "/Users/alex/Projects/demo"
        let sessionId = "session-1"
        let eventsDir = GrokPaths.eventsFile(home: home, cwd: cwd, sessionId: sessionId)
            .deletingLastPathComponent()
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let sessions = """
        [{"session_id":"\(sessionId)","pid":1234,"cwd":"\(cwd)","opened_at":"2026-09-01T00:00:00Z"}]
        """
        try sessions.write(
            to: GrokPaths.activeSessions(home: home),
            atomically: true,
            encoding: .utf8
        )
        try """
        {"type":"turn_started"}
        {"type":"phase_changed","phase":"permission_prompt"}
        {"type":"permission_requested","tool_name":"run_terminal_command"}

        """.write(
            to: GrokPaths.eventsFile(home: home, cwd: cwd, sessionId: sessionId),
            atomically: true,
            encoding: .utf8
        )

        let alive = StatusEvaluator(isProcessAlive: { $0 == 1234 })
        #expect(alive.evaluate(home: home) == .waitingForInput)

        let dead = StatusEvaluator(isProcessAlive: { _ in false })
        #expect(dead.evaluate(home: home) == .inactive)
    }

    @Test func missingHomeIsInactive() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-status-missing-\(UUID().uuidString)")
        #expect(StatusEvaluator(isProcessAlive: { _ in true }).evaluate(home: home) == .inactive)
    }
}

struct WeeklyUsageTests {
    @Test func parsesCreditsConfigLine() {
        let line = """
        {"ts":"2026-09-01T20:39:43.412Z","src":"shell","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":7.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-08-28T19:31:20.465165+00:00","end":"2026-09-04T19:31:20.465165+00:00"}},"subscriptionTier":"SuperGrok Heavy"}}
        """
        let usage = WeeklyUsage.parse(line: line)
        #expect(usage?.usedPercent == 7)
        #expect(usage?.period == .weekly)
        #expect(usage?.tier == "SuperGrok Heavy")
        #expect(usage?.percentLabel == "7%")
        #expect(usage?.title == "Weekly usage")
        #expect(usage?.periodEnd != nil)
    }

    @Test func latestLineWinsFromTail() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly-usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("unified.jsonl")
        try """
        {"ts":"2026-09-01T10:00:00Z","msg":"other"}
        {"ts":"2026-09-01T11:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":12},"subscriptionTier":"SuperGrok"}}
        {"ts":"2026-09-01T12:00:00Z","msg":"noise"}
        {"ts":"2026-09-01T13:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":18.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-09-08T00:00:00Z"}}}}

        """.write(to: log, atomically: true, encoding: .utf8)
        let usage = WeeklyUsage.latest(in: log)
        #expect(usage?.usedPercent == 18)
        #expect(usage?.period == .weekly)
    }

    @Test func missingLogIsNil() {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-unified-\(UUID().uuidString).jsonl")
        #expect(WeeklyUsage.latest(in: log) == nil)
    }

    @Test func resetsPhrase() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let twoDays = now.addingTimeInterval(2 * 86_400 + 3 * 3_600)
        #expect(WeeklyUsage.resetsPhrase(until: twoDays, now: now) == "resets in 2d 3h")
        let fortyMinutes = now.addingTimeInterval(40 * 60)
        #expect(WeeklyUsage.resetsPhrase(until: fortyMinutes, now: now) == "resets in 40m")
        #expect(WeeklyUsage.resetsPhrase(until: now.addingTimeInterval(-10), now: now) == "reset due")
    }

    @Test func resetLabelIncludesDateAndTime() {
        var usage = WeeklyUsage(
            usedPercent: 7,
            period: .weekly,
            periodEnd: Date(timeIntervalSince1970: 1_788_546_680)
        )
        let label = usage.resetLabel(locale: Locale(identifier: "en_GB"))
        #expect(label?.hasPrefix("Resets ") == true)
        #expect(label?.contains(":") == true)
        usage.periodEnd = Date(timeIntervalSince1970: 1_788_000_000)
        let past = usage.resetLabel(locale: Locale(identifier: "en_GB"))
        #expect(past?.hasPrefix("Resets ") == true)
        #expect(past?.contains(":") == true)
    }

    @Test func countdownIncludesDaysHoursMinutesSeconds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let end = now.addingTimeInterval(2 * 86_400 + 3 * 3_600 + 4 * 60 + 5)
        #expect(WeeklyUsage.countdownPhrase(until: end, now: now) == "2d 03h 04m 05s")
        let sameDay = now.addingTimeInterval(3 * 3_600 + 4 * 60 + 5)
        #expect(WeeklyUsage.countdownPhrase(until: sameDay, now: now) == "0d 03h 04m 05s")
        var usage = WeeklyUsage(usedPercent: 1, periodEnd: end)
        #expect(usage.countdownLabel(now: now) == "2d 03h 04m 05s")
        usage.periodEnd = now.addingTimeInterval(-1)
        #expect(usage.countdownLabel(now: now) == "Reset due")
        usage.periodEnd = nil
        #expect(usage.countdownLabel(now: now) == nil)
    }
}

struct AttentionFocusTests {
    private func row(_ id: String, _ light: TrafficLight) -> LiveSession {
        LiveSession(
            session: ActiveSession(sessionId: id, pid: 1, cwd: "/tmp/\(id)"),
            light: light,
            title: id
        )
    }

    @Test func sittingOnIdleTabDoesNotSettleWaiting() {
        let sessions = [row("a", .idle), row("b", .waitingForInput)]
        #expect(
            AttentionFocus.isSettled(light: .waitingForInput, sessions: sessions, seenIDs: ["a"])
                == false
        )
    }

    @Test func waitingSettlesOnlyAfterThatTab() {
        let sessions = [row("a", .idle), row("b", .waitingForInput)]
        #expect(
            AttentionFocus.isSettled(light: .waitingForInput, sessions: sessions, seenIDs: ["b"])
        )
    }

    @Test func twoCompletedNeedBothTabs() {
        let sessions = [row("a", .completed), row("b", .completed)]
        #expect(
            AttentionFocus.isSettled(light: .completed, sessions: sessions, seenIDs: ["a"])
                == false
        )
        #expect(
            AttentionFocus.isSettled(light: .completed, sessions: sessions, seenIDs: ["a", "b"])
        )
    }

    @Test func runningNeverSettlesAttention() {
        let sessions = [row("a", .running)]
        #expect(
            AttentionFocus.isSettled(light: .running, sessions: sessions, seenIDs: ["a"])
                == false
        )
    }
}

struct GrokMarkTests {
    @Test func glyphFillsTheViewBox() {
        let box = GrokMark.cgPath().boundingBoxOfPath
        #expect(box.minX > 40)
        #expect(box.minY > 40)
        #expect(box.maxX < 480)
        #expect(box.maxY < 480)
        #expect(box.width > 250)
        #expect(box.height > 250)
    }
}
