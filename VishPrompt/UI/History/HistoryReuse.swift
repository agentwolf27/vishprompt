import AppKit
import Observation

/// How a paste-again or copy from History ended, worded by `HistoryReuse.message(for:)`.
enum HistoryReuseOutcome: Equatable, Sendable {
    case pasted(app: String)
    case copied
    /// Return with no other app to paste into, so the text was copied instead.
    case copiedNoTarget
    case failed(app: String, reason: String)
}

/// Return pastes a History row again into the app used before History, and ⌘C copies it.
///
/// The target is the last app other than this one to come to the front, so opening History
/// from the menu bar, or clicking back into it later, both paste where the user just was.
@MainActor
@Observable
final class HistoryReuse {
    private(set) var targetName: String?
    private(set) var message: String?
    private(set) var inFlight = false

    @ObservationIgnored private var target: NSRunningApplication?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    init() {
        noteFront(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.noteFront(app) }
        }
    }

    /// Called before History activates, so a first open from the menu bar knows the app.
    func noteFront(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        target = app
        targetName = app.localizedName
    }

    /// Counted onto the row when a history row is named: a copy of the output, or of what was
    /// said. Measurement only.
    var onSignal: ((OutcomeSignal) -> Void)?

    func copy(_ text: String, id: String? = nil, ofWhatWasSaid said: Bool = false) {
        TextRescue.copy(text)
        show(.copied)
        if let id { onSignal?(said ? .copiedSaid(id: id) : .copiedOutput(id: id)) }
    }

    func pasteAgain(_ text: String, id: String? = nil) {
        guard !inFlight else { return }
        guard let target, !target.isTerminated else {
            TextRescue.copy(text)
            show(.copiedNoTarget)
            if let id { onSignal?(.copiedOutput(id: id)) }
            return
        }
        let name = target.localizedName ?? "the app"
        inFlight = true
        Task {
            defer { inFlight = false }
            target.activate()
            // Wait for the app to take the keyboard, or ⌘V lands in History.
            var front = false
            for _ in 0..<20 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                    front = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard front else {
                TextRescue.copy(text)
                show(.failed(app: name, reason: "it didn't come to the front"))
                return
            }
            do {
                try await Inserter().insert(text, strategy: .paste)
                show(.pasted(app: name))
                if let id { onSignal?(.pastedAgain(id: id)) }
            } catch {
                TextRescue.copy(text)
                show(.failed(app: name, reason: error.localizedDescription))
            }
        }
    }

    private func show(_ outcome: HistoryReuseOutcome) {
        message = Self.message(for: outcome)
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { message = nil }
        }
    }

    /// The hint under the list when nothing has just happened.
    static func hint(target: String?) -> String {
        target.map { "Return pastes it into \($0) · ⌘C copies" } ?? "⌘C copies · open History from another app to paste with Return"
    }

    static func message(for outcome: HistoryReuseOutcome) -> String {
        switch outcome {
        case let .pasted(app):
            "Pasted into \(app)."
        case .copied:
            "Copied."
        case .copiedNoTarget:
            "Copied. There was no other app to paste into, so click where it goes and press ⌘V."
        case let .failed(app, reason):
            "Couldn't paste into \(app) (\(reason.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))). It's copied, so press ⌘V there."
        }
    }
}
