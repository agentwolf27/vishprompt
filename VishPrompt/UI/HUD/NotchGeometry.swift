import AppKit
import Foundation

/// Where the overlay goes on a screen: two lobes beside the camera housing on a notched
/// built-in display, or a free capsule under the menu bar everywhere else.
///
/// The notch is read, never assumed: `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are the
/// usable strips either side of the housing, and only a screen that reports both, with a top
/// safe-area inset, has one. Anything else gets the free capsule, and the housing itself is
/// never drawn over or imitated: a fake notch on a display without one was NotchNook's mistake.
struct NotchLayout: Equatable, Sendable {
    /// Width of the gap the camera housing occupies. Left transparent.
    var notchWidth: CGFloat
    /// Height of the menu bar strip the lobes sit in.
    var barHeight: CGFloat
    /// Each lobe's width.
    var lobeWidth: CGFloat
    /// Horizontal centre of the housing, in screen coordinates.
    var notchMidX: CGFloat

    /// Room for a mode chip and "into Claude Code" on the left, the meter and the time on the
    /// right. 150 pt cut "Claude Code" short.
    static let lobeWidth: CGFloat = 180

    var totalWidth: CGFloat { lobeWidth * 2 + notchWidth }
}

enum NotchGeometry {
    /// The lobes for a screen, or nil when it has no notch.
    static func layout(
        screenFrame: CGRect,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?,
        safeAreaTop: CGFloat,
        lobeWidth: CGFloat = NotchLayout.lobeWidth
    ) -> NotchLayout? {
        guard let left = auxiliaryTopLeft, let right = auxiliaryTopRight, safeAreaTop > 0 else { return nil }
        let notchWidth = right.minX - left.maxX
        // A housing has some width, and there must be room either side for a lobe.
        guard notchWidth > 0,
              left.width >= lobeWidth, right.width >= lobeWidth
        else { return nil }
        return NotchLayout(
            notchWidth: notchWidth,
            barHeight: safeAreaTop,
            lobeWidth: lobeWidth,
            notchMidX: left.maxX + notchWidth / 2
        )
    }

    @MainActor
    static func layout(for screen: NSScreen) -> NotchLayout? {
        layout(
            screenFrame: screen.frame,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea,
            safeAreaTop: screen.safeAreaInsets.top
        )
    }

    /// The panel's origin. With lobes, its top is the top of the screen, centred on the
    /// housing; otherwise it is centred 8 pt under the menu bar (or under the top edge, in a
    /// full-screen app where the menu bar is hidden).
    static func origin(
        panelSize: CGSize,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        notch: NotchLayout?,
        gapBelowMenuBar: CGFloat
    ) -> CGPoint {
        if let notch {
            return CGPoint(x: notch.notchMidX - panelSize.width / 2, y: screenFrame.maxY - panelSize.height)
        }
        return CGPoint(x: visibleFrame.midX - panelSize.width / 2, y: visibleFrame.maxY - panelSize.height - gapBelowMenuBar)
    }

    /// The screen the overlay should use: the one holding the pointer.
    @MainActor
    static var pointerScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}
