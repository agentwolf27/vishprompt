import Foundation
import Synchronization

/// The Anthropic API key, read from the Keychain once and kept in memory.
///
/// Every API request used to read the Keychain, which is a round trip to securityd on the
/// latency path. The key changes only when the user saves or removes it in Settings, and
/// `Keychain` clears this cache when that happens, so the next read sees the change.
final class APIKeyCache: Sendable {
    static let shared = APIKeyCache()

    private enum Entry: Sendable {
        case unread
        case read(String?)
    }

    private let entry = Mutex<Entry>(.unread)
    private let reader: @Sendable () -> String?

    /// Tests pass their own reader; the app reads the Keychain.
    init(reader: @escaping @Sendable () -> String? = { try? Keychain.get(.anthropicAPIKey) }) {
        self.reader = reader
    }

    /// The key, or nil when none is stored. Reads the Keychain only the first time.
    func value() -> String? {
        entry.withLock { state in
            if case let .read(value) = state { return value }
            let value = reader().flatMap { $0.isEmpty ? nil : $0 }
            state = .read(value)
            return value
        }
    }

    var hasKey: Bool { value() != nil }

    /// Forgets the cached value, so the next read goes back to the Keychain.
    func invalidate() {
        entry.withLock { $0 = .unread }
    }
}
