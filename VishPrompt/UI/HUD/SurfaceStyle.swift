import AppKit
import SwiftUI

/// The overlay's surface, decided in one place: Liquid Glass on macOS 26 when the app was built
/// with an SDK that has it, the thin material everywhere else.
///
/// Glass handles Reduce Transparency ("frostier"), Increase Contrast and Reduce Motion itself,
/// so only the material path needs a stronger border for Increase Contrast. The notch lobes are
/// not a surface in this sense: they are black so they read as part of the housing, and stay so.
enum SurfaceStyle: Equatable, Sendable {
    case glass
    case material

    /// Whether this build's SDK has the glass APIs. Swift 6.2 ships with the macOS 26 SDK; an
    /// older Xcode cannot even name them, so the glass path is compiled out, not merely skipped.
    static var sdkHasGlass: Bool {
        #if compiler(>=6.2)
        true
        #else
        false
        #endif
    }

    static func resolve(osMajorVersion: Int, sdkHasGlass: Bool) -> SurfaceStyle {
        sdkHasGlass && osMajorVersion >= 26 ? .glass : .material
    }

    static var current: SurfaceStyle {
        resolve(osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion, sdkHasGlass: sdkHasGlass)
    }

    /// The material path's edge. Increase Contrast asks for a border that can actually be seen.
    static func borderOpacity(increasedContrast: Bool) -> Double {
        increasedContrast ? 0.5 : 0.1
    }
}

/// Which piece of the overlay a surface is for. The card carries sentences, so its material
/// is a step thicker than the capsule's.
enum SurfaceRole {
    case capsule
    case card

    var material: Material {
        switch self {
        case .capsule: .ultraThinMaterial
        case .card: .regularMaterial
        }
    }
}

extension View {
    /// The overlay's surface for `role`, in `shape`.
    func hudSurface<S: InsettableShape>(_ role: SurfaceRole, in shape: S) -> some View {
        modifier(HUDSurface(role: role, shape: shape))
    }
}

private struct HUDSurface<S: InsettableShape>: ViewModifier {
    let role: SurfaceRole
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        switch SurfaceStyle.current {
        case .glass:
            glass(content)
        case .material:
            material(content)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            material(content)
        }
        #else
        material(content)
        #endif
    }

    private func material(_ content: Content) -> some View {
        content
            .background(role.material, in: shape)
            .overlay(
                shape.strokeBorder(.white.opacity(SurfaceStyle.borderOpacity(increasedContrast: contrast == .increased)), lineWidth: 1)
            )
    }
}
