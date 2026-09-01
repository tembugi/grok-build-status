import Foundation
import GrokStatusCore

final class GrokMonitor: @unchecked Sendable {
    private let home: URL
    private let onChange: @Sendable (TrafficLight) -> Void
    private let queue = DispatchQueue(label: "dev.teemu.GrokStatus.monitor")
    private var watcher: FolderWatcher?
    private var readers: [String: EventFileReader] = [:]
    private var lastSessions: [ActiveSession] = []
    private var lastLight: TrafficLight?

    init(home: URL = GrokPaths.home(), onChange: @escaping @Sendable (TrafficLight) -> Void) {
        self.home = home
        self.onChange = onChange
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.refresh()
            let watcher = FolderWatcher(path: self.home.path, queue: self.queue) { [weak self] in
                self?.refresh()
            }
            watcher.start()
            self.watcher = watcher
        }
    }

    private func refresh() {
        if let sessions = ActiveSessions.load(from: GrokPaths.activeSessions(home: home)) {
            lastSessions = sessions
        }

        let live = lastSessions.filter { ProcessLiveness.isAlive($0.pid) }
        let liveIDs = Set(live.map(\.sessionId))
        readers = readers.filter { liveIDs.contains($0.key) }

        var light = TrafficLight.inactive
        for session in live {
            let reader = readers[session.sessionId] ?? EventFileReader()
            reader.readNew(
                from: GrokPaths.eventsFile(home: home, cwd: session.cwd, sessionId: session.sessionId)
            )
            readers[session.sessionId] = reader
            light = light.combining(reader.state.light)
        }

        if light != lastLight {
            lastLight = light
            onChange(light)
        }
    }
}
