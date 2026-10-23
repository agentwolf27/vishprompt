import AppKit
import SwiftUI

/// Draws a view through a real hosting view, which renders scroll views and materials the way
/// a window does (ImageRenderer leaves a ScrollView blank), and saves it as a PNG.
@MainActor
enum HUDSnapshot {
    static func write<Content: View>(_ view: Content, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.padding(20).background(Color(white: 0.85)))
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
    }
}
