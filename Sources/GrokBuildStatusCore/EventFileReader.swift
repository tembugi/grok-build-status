import Foundation

public final class EventFileReader: @unchecked Sendable {
    public private(set) var state = SessionRuntimeState()
    private var offset: UInt64 = 0
    private var pending = Data()
    private static let maxPendingBytes = 262_144

    public init() {}

    public func readNew(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            reset()
            return
        }
        let size: UInt64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let value = attrs[.size] as? NSNumber
        {
            size = value.uint64Value
        } else {
            return
        }
        if size == offset { return }
        if size < offset {
            reset()
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            // Advance by bytes actually read, not the size sampled before
            // the read — the file can grow in between.
            offset += UInt64(data.count)
            ingest(data)
        } catch {
            return
        }
    }

    private func reset() {
        offset = 0
        pending = Data()
        state = SessionRuntimeState()
    }

    public func ingest(_ data: Data) {
        pending.append(data)
        if pending.count > Self.maxPendingBytes {
            reset()
            return
        }
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
