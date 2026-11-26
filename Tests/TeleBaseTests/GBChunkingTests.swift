import XCTest
@testable import TeleBase

final class TBChunkingTests: XCTestCase {

    func testHeaderOnlyMessageFitsCaption() throws {
        let record = try TBRecord(key: "profile:7", ownerId: 7, payload: TBProfile(displayName: "A", bio: "B"))
        let messages = try TBCodec.messages(for: record)
        XCTAssertGreaterThanOrEqual(messages.count, 2)
        XCTAssertEqual(messages.first, "TB1|profile:7")
        XCTAssertLessThanOrEqual(messages[0].count, TBCodec.maxCaptionLength)
    }

    func testChunksRespectMessageLimit() throws {
        let longBio = String(repeating: "x", count: 20_000)
        let record = try TBRecord(key: "profile:7", ownerId: 7, payload: TBProfile(displayName: "A", bio: longBio))
        let messages = try TBCodec.messages(for: record)
        XCTAssertGreaterThan(messages.count, 2)
        for message in messages {
            XCTAssertLessThanOrEqual(message.count, TBCodec.maxMessageLength)
        }
    }

    func testAssembleReconstructsChunkedRecord() throws {
        let profile = TBProfile(displayName: "Long",
                                bio: String(repeating: "y", count: 9_000),
                                links: ["site": "https://example.com"])
        let record = try TBRecord(key: TBProfile.recordKey(ownerId: 7),
                                  ownerId: 7,
                                  updatedAt: Date(timeIntervalSince1970: 1_764_110_400),
                                  payload: profile)
        let messages = try TBCodec.messages(for: record)
        let assembled = TBCodec.assemble(messages: messages)
        XCTAssertEqual(assembled, record)
    }

    func testAssembleFailsOnMissingChunk() throws {
        let record = try TBRecord(key: "profile:7",
                                  ownerId: 7,
                                  payload: TBProfile(displayName: "A", bio: String(repeating: "z", count: 9_000)))
        var messages = try TBCodec.messages(for: record)
        XCTAssertGreaterThan(messages.count, 3)
        messages.remove(at: 2) // drop a middle chunk
        XCTAssertNil(TBCodec.assemble(messages: messages))
    }

    func testAssembleAcceptsSingleMessageForm() throws {
        let record = try TBRecord(key: "profile:7", ownerId: 7, payload: TBProfile(displayName: "A", bio: "B"))
        let single = try TBCodec.encode(record)
        XCTAssertEqual(TBCodec.assemble(messages: [single]), record)
    }
}
