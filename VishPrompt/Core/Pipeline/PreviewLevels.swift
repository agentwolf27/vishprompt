import Foundation

/// Every level a preview has been compiled at, so going back is instant.
///
/// On the subscription a compile takes 6 to 10 seconds. Without this, Tab forward then back
/// cost three recompiles to see text that was already on screen a moment ago.
struct PreviewLevels: Equatable, Sendable {
    private(set) var results: [EditLevel: CompiledPrompt] = [:]

    mutating func store(_ prompt: CompiledPrompt, requested level: EditLevel) {
        results[level] = prompt
    }

    func cached(_ level: EditLevel) -> CompiledPrompt? {
        results[level]
    }

    /// The level before this one, wrapping around: what ⇧Tab moves to.
    static func previous(before level: EditLevel) -> EditLevel {
        switch level {
        case .verbatim: .full
        case .light: .verbatim
        case .medium: .light
        case .full: .medium
        }
    }

    /// The level a number key jumps to: 1 verbatim, 2 light, 3 organised, 4 compiled.
    static func level(forNumber number: Int) -> EditLevel? {
        switch number {
        case 1: .verbatim
        case 2: .light
        case 3: .medium
        case 4: .full
        default: nil
        }
    }

    /// How far ↑ and ↓ move the preview, in lines.
    static let scrollStep = 4
}
