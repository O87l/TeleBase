import XCTest
@testable import TeleBase

final class TBResolverTests: XCTestCase {

    private func record(key: String = "profile:7", owner: Int64 = 7, at time: TimeInterval, bio: String) throws -> TBRecord {
        try TBRecord(key: key,
                     ownerId: owner,
                     updatedAt: Date(timeIntervalSince1970: time),
                     payload: TBProfile(displayName: "A", bio: bio))
    }

    func testNewestWins() throws {
        let old = try record(at: 100, bio: "old")
        let new = try record(at: 200, bio: "new")
        let winner = TBResolver.newest([old, new], forKey: "profile:7")
        XCTAssertEqual(winner, new)
        XCTAssertEqual(TBResolver.newest([new, old], forKey: "profile:7"), new)
        XCTAssertNil(TBResolver.newest([old, new], forKey: "profile:99"))
    }

    func testVerifiedMessagesFilterByPoster() {
        let mine = TBTransportMessage(id: 1, posterId: 7, text: "TB1|profile:7")
        let foreign = TBTransportMessage(id: 2, posterId: 999, text: "TB1|profile:7")
        let kept = TBResolver.verifiedMessages([mine, foreign], ownerId: 7)
        XCTAssertEqual(kept, [mine])
    }

    /// End-to-end over the mock transport: the owner publishes, an impostor
    /// tries to overwrite the record with a newer timestamp, and readers
    /// must still get the owner's copy.
    func testRegistryClientRejectsImpostor() async throws {
        let transport = MockGroupTransport(currentUserId: 7)
        let cache = TBDiskCache(directory: temporaryDirectory(), ttl: 60)
        let client = TBRegistryClient(transport: transport, cache: cache)

        let mine = TBProfile(displayName: "Real", bio: "mine")
        try await client.publish(mine, key: TBProfile.recordKey(ownerId: 7))

        // Impostor: a complete, newer publication claiming ownerId 7,
        // but posted by account 999.
        let fake = try TBRecord(key: TBProfile.recordKey(ownerId: 7),
                                ownerId: 7,
                                updatedAt: Date().addingTimeInterval(3600),
                                payload: TBProfile(displayName: "Fake", bio: "impostor"))
        for message in try TBCodec.messages(for: fake) {
            transport.inject(text: message, posterId: 999)
        }

        // Force a fresh read (publishing populated the cache).
        client.invalidate(key: TBProfile.recordKey(ownerId: 7))
        let fetched = try await client.fetch(key: TBProfile.recordKey(ownerId: 7), as: TBProfile.self)
        XCTAssertEqual(fetched, mine)
    }

    func testRegistryClientRoundTrip() async throws {
        let transport = MockGroupTransport(currentUserId: 7)
        let client = TBRegistryClient(transport: transport,
                                      cache: TBDiskCache(directory: temporaryDirectory(), ttl: 60))
        let profile = TBProfile(displayName: "Abd", bio: "hello", bannerURL: "https://example.com/b.png")
        try await client.publish(profile, key: TBProfile.recordKey(ownerId: 7))
        client.invalidate(key: TBProfile.recordKey(ownerId: 7))
        let fetched = try await client.fetch(key: TBProfile.recordKey(ownerId: 7), as: TBProfile.self)
        XCTAssertEqual(fetched, profile)
        // The client must leave the group after operating.
        XCTAssertFalse(transport.isJoined)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TeleBaseTests-\(UUID().uuidString)")
    }
}
