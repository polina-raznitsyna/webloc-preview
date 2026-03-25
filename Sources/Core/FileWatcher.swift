import Foundation

public final class FileWatcher: @unchecked Sendable {
    public typealias Callback = @Sendable (String) -> Void

    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let callback: Callback
    private let exclusionFilter: ExclusionFilter

    public init(paths: [String], exclusions: [String] = [], callback: @escaping Callback) {
        self.paths = paths
        self.callback = callback
        self.exclusionFilter = ExclusionFilter(customExclusions: exclusions)
    }

    public func start() {
        let context = UnsafeMutableRawPointer(
            Unmanaged.passRetained(CallbackWrapper(watcher: self)).toOpaque()
        )

        var streamContext = FSEventStreamContext(
            version: 0, info: context, retain: nil, release: nil, copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &streamContext,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func handleEvent(path: String) {
        guard path.hasSuffix(".webloc") else { return }
        guard !exclusionFilter.shouldExclude(path) else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }
        callback(path)
    }
}

private class CallbackWrapper {
    let watcher: FileWatcher
    init(watcher: FileWatcher) { self.watcher = watcher }
}

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let wrapper = Unmanaged<CallbackWrapper>.fromOpaque(info).takeUnretainedValue()
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

    for i in 0..<numEvents {
        let flags = eventFlags[i]
        let isCreated = flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
        let isRenamed = flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
        if isCreated || isRenamed {
            wrapper.watcher.handleEvent(path: paths[i])
        }
    }
}
