import Foundation
import CoreServices

final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let path: String
    private let queue: DispatchQueue
    private let latency: CFTimeInterval
    private let fileEvents: Bool
    private let matching: ((String) -> Bool)?
    private let handler: () -> Void

    init(
        path: String,
        queue: DispatchQueue,
        latency: CFTimeInterval = 0.2,
        fileEvents: Bool = false,
        matching: ((String) -> Bool)? = nil,
        handler: @escaping () -> Void
    ) {
        self.path = path
        self.queue = queue
        self.latency = latency
        self.fileEvents = fileEvents
        self.matching = matching
        self.handler = handler
    }

    func start() {
        stop()
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                .handle(eventPaths: eventPaths)
        }
        var flags = UInt32(kFSEventStreamCreateFlagUseCFTypes)
        if fileEvents {
            flags |= UInt32(kFSEventStreamCreateFlagFileEvents)
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    private func handle(eventPaths: UnsafeMutableRawPointer) {
        if let matching {
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
            let hit = paths.compactMap { $0 as? String }.contains(where: matching)
            guard hit else { return }
        }
        handler()
    }
}
