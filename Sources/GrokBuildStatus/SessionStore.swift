import Foundation
import GrokBuildStatusCore

/// Sole reader of `~/.grok` for the extra. Icon and menu only see snapshots.
final class SessionStore: @unchecked Sendable {
    private let home: URL
    private let onChange: @Sendable (SessionSnapshot) -> Void
    private let queue = DispatchQueue(label: "dev.teemu.GrokBuildStatus.store")
    private var watcher: FolderWatcher?
    private var poll: DispatchSourceTimer?
    private var debounceWork: DispatchWorkItem?
    private var readers: [String: EventFileReader] = [:]
    private var lastSessions: [ActiveSession] = []
    private var lastSnapshot: SessionSnapshot?
    private var lastLights: [String: Int] = [:]
    private var lastActiveStamp: (mtime: Date?, size: UInt64)?
    private let usageReader = WeeklyUsageReader()

    init(
        home: URL = GrokPaths.home(),
        onChange: @escaping @Sendable (SessionSnapshot) -> Void
    ) {
        self.home = home
        self.onChange = onChange
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.publish()
            let watcher = FolderWatcher(
                path: self.home.path,
                queue: self.queue,
                latency: 0.2,
                fileEvents: true,
                matching: Self.isWatchedPath
            ) { [weak self] in
                self?.schedulePublish()
            }
            watcher.start()
            self.watcher = watcher

            // FSEvents is the live path. Slow poll is only a safety net.
            let poll = DispatchSource.makeTimerSource(queue: self.queue)
            poll.schedule(deadline: .now() + 3, repeating: 3)
            poll.setEventHandler { [weak self] in
                self?.publish()
            }
            poll.resume()
            self.poll = poll
        }
    }

    private func schedulePublish() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.publish()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func publish() {
        let snapshot = capture()
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        onChange(snapshot)
    }

    private func capture() -> SessionSnapshot {
        let activeURL = GrokPaths.activeSessions(home: home)
        let activeStamp = fileStamp(activeURL)
        if activeStamp.mtime != lastActiveStamp?.mtime || activeStamp.size != lastActiveStamp?.size {
            lastActiveStamp = activeStamp
            if let sessions = ActiveSessions.load(from: activeURL) {
                lastSessions = sessions
            }
        }
        let live = lastSessions.filter { ProcessLiveness.isAlive($0.pid) }
        let liveIDs = Set(live.map(\.sessionId))
        readers = readers.filter { liveIDs.contains($0.key) }

        var states: [SessionState] = []
        states.reserveCapacity(live.count)
        var light = TrafficLight.inactive
        var lights: [String: Int] = [:]
        for session in live {
            let reader = readers[session.sessionId] ?? EventFileReader()
            reader.readNew(
                from: GrokPaths.eventsFile(home: home, cwd: session.cwd, sessionId: session.sessionId)
            )
            readers[session.sessionId] = reader
            light = light.combining(reader.state.light)
            lights[session.sessionId] = reader.state.light.rawValue
            states.append(SessionState(session: session, light: reader.state.light))
        }

        let usage = usageReader.readNew(from: GrokPaths.unifiedLog(home: home))
        let sessionsUnchanged = lights == lastLights
        let usageUnchanged = usage == lastSnapshot?.usage

        if sessionsUnchanged, usageUnchanged, let lastSnapshot {
            return lastSnapshot
        }

        let sessions: [LiveSession]
        if sessionsUnchanged, let lastSnapshot {
            sessions = lastSnapshot.sessions
        } else {
            sessions = SessionRoster.labeled(states, home: home)
        }

        lastLights = lights
        return SessionSnapshot(light: light, sessions: sessions, usage: usage)
    }

    /// Live session list, event tails, billing log, and titles for duplicate folders.
    private static func isWatchedPath(_ path: String) -> Bool {
        path.hasSuffix("active_sessions.json")
            || path.hasSuffix("events.jsonl")
            || path.hasSuffix("unified.jsonl")
            || path.hasSuffix("summary.json")
    }

    private func fileStamp(_ url: URL) -> (mtime: Date?, size: UInt64) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = attrs?[.modificationDate] as? Date
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        return (mtime, size)
    }
}
