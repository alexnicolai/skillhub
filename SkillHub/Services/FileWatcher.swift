import Foundation
import CoreServices

/// FSEvents-based watcher over the canonical store + all tool skill dirs.
/// Debounced; a generation counter lets SkillHub ignore events caused by its
/// own writes (bump `suppress()` around engine operations).
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private var pending: DispatchWorkItem?
    private var suppressedUntil: Date = .distantPast

    init(paths: [URL], debounce: TimeInterval = 0.5, onChange: @escaping () -> Void) {
        self.debounce = debounce
        self.onChange = onChange
        start(paths: paths.filter { FileManager.default.fileExists(atPath: $0.path) })
    }

    deinit { stop() }

    /// Ignore events for the next `seconds` (call before engine-driven writes).
    func suppress(for seconds: TimeInterval = 2.0) {
        suppressedUntil = Date().addingTimeInterval(seconds)
    }

    private func start(paths: [URL]) {
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handleEvent()
        }
        stream = FSEventStreamCreate(
            nil, callback, &context,
            paths.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounce,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    private func handleEvent() {
        guard Date() >= suppressedUntil else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }
}
