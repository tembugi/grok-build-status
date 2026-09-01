import Foundation

public final class EventFileReader: @unchecked Sendable {
    public private(set) var state = SessionRuntimeState()
    private var offset: UInt64 = 0
    private var pending = Data()

    public init() {}

    public func readNew(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return }
        if size < offset {
            offset = 0
            pending = Data()
            state = SessionRuntimeState()
        }

        do {
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            offset = size
            ingest(data)
        } catch {
            return
        }
    }

    public func ingest(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstRange(of: Data([0x0A])) {
            let line = pending.subdata(in: pending.startIndex..<newline.lowerBound)
            pending.removeSubrange(..<newline.upperBound)
            apply(line)
        }
    }

    private func apply(_ line: Data) {
        guard !line.isEmpty, let event = EventLine.parse(line) else { return }
        state.apply(event)
    }
}
