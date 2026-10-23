import AppKit
import Foundation

extension Notification.Name {
    /// Visprflow itself wrote to the clipboard: a paste's restore, or text handed back after a
    /// failed insert. Not something the user copied, so it must not look fresh.
    static let visprflowWroteClipboard = Notification.Name("com.vish.visprflow.wroteClipboard")
}

/// Notices when the clipboard changes and whether the new contents are an image, so a
/// screenshot copied a moment ago can be picked up by "fix this".
///
/// It reads the change count and the list of types, never the contents: what was copied stays
/// unread until the user asks for it. Changes Visprflow makes itself are ignored, otherwise
/// every paste's restore would make an old screenshot look newly copied.
@MainActor
final class ClipboardWatcher {
    private let pasteboard: NSPasteboard
    private var lastCount: Int
    private(set) var lastChange: Date?
    private(set) var lastChangeWasImage = false
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observer = NotificationCenter.default.addObserver(forName: .visprflowWroteClipboard, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.resync() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// Checks for a change now. The timer calls this; so do tests.
    func poll(now: Date = Date()) {
        let count = pasteboard.changeCount
        guard count != lastCount else { return }
        lastCount = count
        lastChange = now
        let types = Set(pasteboard.types ?? [])
        lastChangeWasImage = !types.isDisjoint(with: ClipboardReader.imageTypes) && !types.contains(.string)
    }

    /// Accepts the current contents as already seen, without calling them new.
    func resync() {
        lastCount = pasteboard.changeCount
    }

    /// Seconds since an image was copied, or nil when the latest copy is not an image or was
    /// made before Visprflow started watching.
    func imageAge(now: Date = Date()) -> TimeInterval? {
        poll(now: now)
        guard lastChangeWasImage, let lastChange else { return nil }
        return now.timeIntervalSince(lastChange)
    }
}
