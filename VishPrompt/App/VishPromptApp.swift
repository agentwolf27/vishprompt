import SwiftUI

@main
struct VishPromptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(delegate.state)
        } label: {
            // Read through a View so Observation actually tracks it. Reading
            // `state.permissions` directly in this builder samples it once, during Scene
            // construction, and the icon would never update.
            MenuBarIcon(state: delegate.state)
        }
        .menuBarExtraStyle(.menu)
    }
}
