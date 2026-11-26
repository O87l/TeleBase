import Foundation

/// A small file-backed string cache with a time-to-live.
///
/// TeleBase uses it to avoid hammering Telegram: registry reads are served
/// from the cache for up to 24 hours by default (the TTL the original Urgram
/// registry used), and broadcast config falls back to the last good copy
/// when the network is unavailable.
///
/// The cache stores plain strings (usually `TBCodec`-encoded records or
/// config JSON). It is deliberately simple: one JSON file, an in-memory
/// dictionary, and a lock. It is not a database — when it is gone, the
/// group still holds the truth.
public final class TBDiskCache {

    struct Entry: Codable {
        var value: String
        var storedAt: TimeInterval
    }

    /// How long an entry stays valid. Default: 24 hours.
    public let ttl: TimeInterval

    private let fileURL: URL
    private let now: () -> Date
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    /// Creates a cache in the given directory.
    /// - Parameters:
    ///   - directory: Folder that holds the cache file. Created if needed.
    ///   - ttl: Entry lifetime in seconds. Default 24 hours.
    public init(directory: URL, ttl: TimeInterval = 24 * 60 * 60) {
        self.fileURL = directory.appendingPathComponent("telebase-cache.json")
        self.ttl = ttl
        self.now = { Date() }
        load()
    }

    /// Test-friendly initializer with an injectable clock.
    init(directory: URL, ttl: TimeInterval, now: @escaping () -> Date) {
        self.fileURL = directory.appendingPathComponent("telebase-cache.json")
        self.ttl = ttl
        self.now = now
        load()
    }

    /// The default cache, stored in the system caches directory.
    public static func defaultCache(ttl: TimeInterval = 24 * 60 * 60) -> TBDiskCache {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return TBDiskCache(directory: base.appendingPathComponent("TeleBase"), ttl: ttl)
    }

    // MARK: - Reading & writing

    /// Returns the cached value for `key`, or `nil` when missing or expired.
    public func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        if now().timeIntervalSince1970 - entry.storedAt > ttl {
            entries.removeValue(forKey: key)
            persistLocked()
            return nil
        }
        return entry.value
    }

    /// Stores a value and persists the cache to disk.
    public func set(_ value: String, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = Entry(value: value, storedAt: now().timeIntervalSince1970)
        persistLocked()
    }

    /// Removes a single entry.
    public func remove(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key)
        persistLocked()
    }

    /// Removes every entry.
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        persistLocked()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return
        }
        entries = decoded
    }

    /// Must be called with `lock` held.
    private func persistLocked() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}
