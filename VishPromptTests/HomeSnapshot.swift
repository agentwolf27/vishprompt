import AppKit
import GRDB
import SwiftUI
@testable import VishPrompt

/// Renders a Home window view at a fixed size in light or dark, for pixel checks and for the
/// PNGs written when TEST_RUNNER_VISHPROMPT_SNAPSHOTS names a directory.
@MainActor
enum HomeSnapshot {
    static func render<Content: View>(_ view: Content, size: CGSize, dark: Bool) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI settle onAppear work, such as loading the rows.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    /// Writes the PNG when a snapshot directory is set. Returns the bitmap either way.
    @discardableResult
    static func capture<Content: View>(_ view: Content, size: CGSize, dark: Bool, name: String) -> NSBitmapImageRep? {
        let bitmap = render(view, size: size, dark: dark)
        if let directory = ProcessInfo.processInfo.environment["VISHPROMPT_SNAPSHOTS"], let bitmap,
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: directory).appending(path: "\(name)-\(dark ? "dark" : "light").png"))
        }
        return bitmap
    }

    /// The colour at a point given in view coordinates (origin top left), in sRGB 0–255.
    static func pixel(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat, viewSize: CGSize) -> (Int, Int, Int)? {
        let scaleX = CGFloat(bitmap.pixelsWide) / viewSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / viewSize.height
        // The raw stored components: SwiftUI writes the sRGB values as given, and converting
        // from the bitmap's display profile would shift them by up to 9 levels.
        guard let color = bitmap.colorAt(x: Int(x * scaleX), y: Int(y * scaleY)), color.numberOfComponents >= 3 else { return nil }
        return (Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }

    static func matches(_ pixel: (Int, Int, Int)?, _ rgb: RGB, tolerance: Int = 3) -> Bool {
        guard let pixel else { return false }
        let want = (Int((rgb.red * 255).rounded()), Int((rgb.green * 255).rounded()), Int((rgb.blue * 255).rounded()))
        return abs(pixel.0 - want.0) <= tolerance && abs(pixel.1 - want.1) <= tolerance && abs(pixel.2 - want.2) <= tolerance
    }

    /// A morning's worth of history, fixed so snapshots are stable.
    static func sampleQueue(now: Date) throws -> DatabaseQueue {
        let queue = try Database.makeQueue(path: nil)
        let rows: [(String, TimeInterval, String, String, String?, String, DictationRecord.Status)] = [
            ("a1", 3 * 60, "message", "the deploy is done error rate back to normal ill watch it till six",
             "The deploy is done and the error rate is back to normal. I’ll keep an eye on it until 6.", "local", .inserted),
            ("a2", 14 * 60, "claude_code", "fix the auth test it’s flaky don’t touch the fixtures",
             "Goal: make test_auth_refresh pass reliably. Constraints: do not change Fixtures/; keep the other auth tests green.", "subscription", .inserted),
            ("a3", 47 * 60, "email", "thanks for the intro happy to chat any time next week",
             "Thanks for the intro, happy to chat any time next week.", "local", .inserted),
            ("a4", 65 * 60, "document", "as bullet points keep the numbers",
             "• Q3 signups: 1,240 (up from 980)\n• Churn: 3.1%\n• Next: pricing test starts Monday", "local", .inserted),
            ("a5", 26 * 3600, "claude_code", "fix this",
             "Fix the crash when an order has no customer. Error: TypeError reading “id” at getOrder (src/routes/order.ts:42).", "subscription", .inserted),
        ]
        try queue.write { db in
            for (id, ago, destination, said, out, provider, status) in rows {
                try DictationRecord(id: id, createdAt: now.addingTimeInterval(-ago), destination: destination, level: "full",
                                    rawTranscript: said, compiledText: out, requestJSON: nil, status: status, provider: provider).insert(db)
            }
        }
        return queue
    }

    /// 10:45 this morning.
    static var morning: Date {
        Calendar.current.date(bySettingHour: 10, minute: 45, second: 0, of: Date())!
    }
}
