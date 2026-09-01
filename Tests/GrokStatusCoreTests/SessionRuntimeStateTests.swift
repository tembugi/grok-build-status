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

    @Test func autoApprovedPermissionDoesNotStayRed() {
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

    @Test func redOutranksYellow() {
        #expect(TrafficLight.running.combining(.waitingForInput) == .waitingForInput)
        #expect(TrafficLight.idle.combining(.running) == .running)
        #expect(TrafficLight.inactive.combining(.idle) == .idle)
        #expect(TrafficLight.completed.combining(.running) == .running)
        #expect(TrafficLight.idle.combining(.completed) == .completed)
    }
}

struct GrokPathsTests {
    @Test func encodesCwdLikeGrok() {
        #expect(
            GrokPaths.encodeCwd("/Users/teemu/Projects/grok-build-status")
                == "%2FUsers%2Fteemu%2FProjects%2Fgrok-build-status"
        )
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
}

struct StatusEvaluatorTests {
    @Test func usesLiveSessionEvents() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-status-test-\(UUID().uuidString)")
        let cwd = "/Users/teemu/Projects/demo"
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

struct GrokMarkTests {
    @Test func officialGlyphFillsTheViewBox() {
        let box = GrokMark.cgPath().boundingBoxOfPath
        #expect(box.minX > 40)
        #expect(box.minY > 40)
        #expect(box.maxX < 480)
        #expect(box.maxY < 480)
        #expect(box.width > 250)
        #expect(box.height > 250)
    }
}
