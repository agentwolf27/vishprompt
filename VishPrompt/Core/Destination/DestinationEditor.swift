import Foundation
import Observation

/// Edits one destination at a time and saves every change as it is made.
///
/// The settings window used to hold edits in a draft until Save, and switching rows threw the
/// draft away without a word. macOS settings apply immediately; so does this.
@MainActor
@Observable
final class DestinationEditor {
    private let settings: DestinationSettings
    private(set) var selection: String
    /// The override being edited, already saved.
    private(set) var current: DestinationOverride

    init(settings: DestinationSettings = DestinationSettings(), selection: String = Destination.claudeCode.id) {
        self.settings = settings
        self.selection = selection
        self.current = settings.override(for: selection) ?? DestinationOverride()
    }

    func select(_ id: String) {
        guard id != selection else { return }
        selection = id
        current = settings.override(for: id) ?? DestinationOverride()
    }

    /// Applies a change and saves it straight away.
    func update(_ change: (inout DestinationOverride) -> Void) {
        change(&current)
        settings.setOverride(Self.normalised(current), for: selection)
    }

    func reset() {
        current = DestinationOverride()
        settings.setOverride(nil, for: selection)
    }

    func override(for id: String) -> DestinationOverride? {
        settings.override(for: id)
    }

    /// Blank instructions are no instructions; an override with nothing in it is removed.
    static func normalised(_ value: DestinationOverride) -> DestinationOverride? {
        var result = value
        if result.instructions?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            result.instructions = nil
        }
        return result == DestinationOverride() ? nil : result
    }
}
