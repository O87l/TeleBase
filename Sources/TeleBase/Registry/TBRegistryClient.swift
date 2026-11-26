import Foundation

/// The registry client: publish and fetch records in a Telegram group.
///
/// Reads are cache-first (24h by default, see `TBDiskCache`). On a cache
/// miss the client joins the group, searches for the record's header,
/// reassembles candidate records **per poster**, keeps only the copies
/// whose envelope owner matches the account that posted them, and resolves
/// conflicts newest-first. It then leaves the group again — the
/// join → operate → leave pattern that keeps the registry group out of the
/// user's chat list.
public final class TBRegistryClient {

    private let transport: GroupTransport
    private let cache: TBDiskCache

    public init(transport: GroupTransport, cache: TBDiskCache = .defaultCache()) {
        self.transport = transport
        self.cache = cache
    }

    // MARK: - Publishing

    /// Publishes a record: a header-only message followed by body chunks.
    ///
    /// The record's `ownerId` should be the transport's `currentUserId` —
    /// readers will (correctly) distrust copies posted by anyone else.
    public func publish(_ record: TBRecord) async throws {
        let messages = try TBCodec.messages(for: record)
        try await withMembership {
            if let header = messages.first {
                try await transport.postHeader(header)
            }
            for chunk in messages.dropFirst() {
                try await transport.post(text: chunk)
            }
        }
        if let encoded = try? TBCodec.encode(record) {
            cache.set(encoded, forKey: cacheKey(record.key))
        }
    }

    /// Publishes a typed payload under `key`, owned by the signed-in user.
    public func publish<Payload: Encodable>(_ payload: Payload, key: String) async throws {
        let record = try TBRecord(key: key,
                                  ownerId: transport.currentUserId,
                                  payload: payload)
        try await publish(record)
    }

    // MARK: - Fetching

    /// Fetches the newest verified record for `key`, or `nil` when the
    /// group holds no trustworthy copy.
    public func fetchRecord(key: String) async throws -> TBRecord? {
        if let cached = cache.string(forKey: cacheKey(key)),
           let record = TBCodec.decode(cached) {
            return record
        }

        let messages = try await withMembership {
            try await transport.search(query: TBCodec.header(forKey: key))
        }

        // Assemble per poster, then verify: the envelope's ownerId must
        // equal the account that posted every message of the copy.
        let byPoster = Dictionary(grouping: messages, by: { $0.posterId })
        var verified: [TBRecord] = []
        for (posterId, group) in byPoster {
            if let record = TBCodec.assemble(messages: group.map { $0.text }),
               record.ownerId == posterId {
                verified.append(record)
            }
        }

        guard let record = TBResolver.newest(verified, forKey: key) else {
            return nil
        }
        if let encoded = try? TBCodec.encode(record) {
            cache.set(encoded, forKey: cacheKey(key))
        }
        return record
    }

    /// Fetches a record and decodes its payload as `Payload`.
    public func fetch<Payload: Decodable>(key: String, as type: Payload.Type) async throws -> Payload? {
        guard let record = try await fetchRecord(key: key) else { return nil }
        return try record.payload(as: Payload.self)
    }

    /// Drops the cached copy of a record, forcing the next fetch to search
    /// the group again.
    public func invalidate(key: String) {
        cache.remove(forKey: cacheKey(key))
    }

    // MARK: - Helpers

    private func cacheKey(_ key: String) -> String {
        "record:" + key
    }

    /// Runs `body` between join and leave, leaving even on failure.
    private func withMembership<T>(_ body: () async throws -> T) async throws -> T {
        try await transport.join()
        do {
            let result = try await body()
            try? await transport.leave()
            return result
        } catch {
            try? await transport.leave()
            throw error
        }
    }
}
