import AppKit
import SwiftUI

/// Hosts the onboarding view in an AppKit window so the app delegate can open it at launch
/// and bring it to the front, which an LSUIElement app has to do explicitly.
@MainActor
final class SetupWindowController: NSWindowController, NSWindowDelegate {
    private weak var state: AppState?

    init(state: AppState) {
        self.state = state
        let host = NSHostingController(rootView: OnboardingView().environment(state))
        let window = NSWindow(contentViewController: host)
        window.title = "VishPrompt Setup"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // Matches the content's minimum (580 × 680), so the window opens at a size the
        // content does not immediately fight.
        window.setContentSize(NSSize(width: 580, height: 680))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SetupWindowController is created in code")
    }

    /// Disarms the trigger recorder when the window closes.
    ///
    /// The recorder swallows the next key pressed anywhere on the system. Left armed after the
    /// window is gone, the next character typed in any app would vanish and silently become the
    /// global trigger.
    func windowWillClose(_ notification: Notification) {
        state?.cancelTriggerRecording()
    }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}


/// The Settings window: General, Providers, Destinations, Vocabulary, Privacy. Its title
/// follows the pane, as the HIG asks, and it reopens on the last pane used.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(state: AppState) {
        let box = WindowBox()
        let host = NSHostingController(rootView: SettingsView(onPaneChange: { pane in
            box.window?.title = pane.title
        }).environment(state))
        let window = NSWindow(contentViewController: host)
        window.title = SettingsPaneStore().last.title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        box.window = window
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is created in code")
    }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Lets the hosted view reach its window without the window owning the view owning it back.
@MainActor
private final class WindowBox {
    weak var window: NSWindow?
}

/// The VishPrompt window: Home, History, Dictionary and Settings. Its sidebar runs up under
/// the traffic lights, so the title bar is transparent and the title hidden.
@MainActor
final class HomeWindowController: NSWindowController {
    private let reuse: HistoryReuse
    let library: HomeLibrary
    private var closeObserver: NSObjectProtocol?

    init(library: HomeLibrary = HomeLibrary()) {
        let reuse = HistoryReuse()
        self.reuse = reuse
        self.library = library
        let host = NSHostingController(rootView: HomeView(library: library, reuse: reuse))
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = "VishPrompt"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.contentMinSize = HomeView.minimumSize
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("VishPromptHome")
        window.appearance = library.appearance.appearance
        window.center()
        super.init(window: window)
        library.onAppearanceChange = { [weak window] choice in window?.appearance = choice.appearance }
        // Closing the window ends a tap test or calibration, so taps go back to doing their job.
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak library] _ in
            MainActor.assumeIsolated { library?.leavePalmRest() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HomeWindowController is created in code")
    }

    func show(page: HomePage? = nil) {
        if let page { library.page = page }
        library.reload()
        library.refreshRetention()
        // The app the user was in, so Return pastes back there.
        reuse.noteFront(NSWorkspace.shared.frontmostApplication)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
