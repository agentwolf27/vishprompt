import AppKit
import SwiftUI

/// The Home window's colours: warm paper in light, warm charcoal in dark, never pure black.
/// Values from the mockup Vish approved (PLAN.md, "Home window").
struct HomeTheme: Equatable, Sendable {
    let background: RGB
    let sidebar: RGB
    let card: RGB
    /// A recessed panel inside a card, such as "What you said".
    let sunk: RGB
    let line: RGB
    let ink: RGB
    let muted: RGB
    let accent: RGB
    /// The selected row in a choice list.
    let accentWash: RGB
    /// "Stayed on this Mac" and "Never".
    let stayedFill: RGB
    let stayedInk: RGB
    /// "Sent to Claude".
    let sentFill: RGB
    let sentInk: RGB

    static let light = HomeTheme(
        background: RGB(0xFAF8F5), sidebar: RGB(0xF3F0EA), card: RGB(0xFFFFFF), sunk: RGB(0xF6F3EE),
        line: RGB(0xE7E2DA), ink: RGB(0x1C1B1A), muted: RGB(0x6B6660), accent: RGB(0x4B5BDC),
        accentWash: RGB(0xF1F2FD),
        stayedFill: RGB(0xE6F4EA), stayedInk: RGB(0x1E5631), sentFill: RGB(0xECEEFC), sentInk: RGB(0x2E3A9E)
    )

    static let dark = HomeTheme(
        background: RGB(0x1A1918), sidebar: RGB(0x151413), card: RGB(0x242322), sunk: RGB(0x1F1E1D),
        line: RGB(0x34322F), ink: RGB(0xF2F0ED), muted: RGB(0xA8A39C), accent: RGB(0x4B5BDC),
        accentWash: RGB(0x2A2D4A),
        stayedFill: RGB(0x1F3A2C), stayedInk: RGB(0x9FDDB6), sentFill: RGB(0x2A2D4A), sentInk: RGB(0xB9C0FF)
    )

    static func `for`(_ scheme: ColorScheme) -> HomeTheme {
        scheme == .dark ? .dark : .light
    }
}

/// An sRGB colour from a hex literal, so the tokens read exactly as the mockup writes them.
struct RGB: Equatable, Sendable {
    let hex: UInt32

    init(_ hex: UInt32) { self.hex = hex }

    var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    var blue: Double { Double(hex & 0xFF) / 255 }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

/// Settings → Appearance. Follows the Mac unless the user picks one.
enum AppearanceChoice: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    static let key = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match the Mac"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// What the window should be forced to, or nil to follow the Mac.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static func saved(in defaults: UserDefaults = .standard) -> AppearanceChoice {
        defaults.string(forKey: key).flatMap(AppearanceChoice.init(rawValue:)) ?? .system
    }
}

/// The theme for the current colour scheme, available to every view in the window.
private struct HomeThemeKey: EnvironmentKey {
    static let defaultValue = HomeTheme.light
}

extension EnvironmentValues {
    var homeTheme: HomeTheme {
        get { self[HomeThemeKey.self] }
        set { self[HomeThemeKey.self] = newValue }
    }
}

/// Reads the colour scheme the window actually has and hands the matching theme down.
struct HomeThemed<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().environment(\.homeTheme, HomeTheme.for(scheme))
    }
}
