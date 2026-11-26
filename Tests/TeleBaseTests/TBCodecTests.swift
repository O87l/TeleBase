import XCTest
@testable import TeleBase

final class TBCodecTests: XCTestCase {

    func testHeaderFormat() {
        XCTAssertEqual(TBCodec.header(forKey: "profile:42"), "TB1|profile:42")
    }

    func testRoundTrip() throws {
        let profile = TBProfile(displayName: "Abd", bio: "iOS dev", links: ["telegram": "https://t.me/example"])
        let record = try TBRecord(key: TBProfile.recordKey(ownerId: 42),
                                  ownerId: 42,
                                  updatedAt: Date(timeIntervalSince1970: 1_764_110_400),
                                  payload: profile)

        let text = try TBCodec.encode(record)
        XCTAssertTrue(text.hasPrefix("TB1|profile:42\n"))

        let decoded = TBCodec.decode(text)
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(try decoded?.payload(as: TBProfile.self), profile)
    }

    func testDecodeRejectsForeignText() {
        XCTAssertNil(TBCodec.decode("just a normal group message"))
        XCTAssertNil(TBCodec.decode("GB2|profile:42\n{}"))
        XCTAssertNil(TBCodec.key(fromMessage: "hello"))
    }

    func testKeyExtractionFromChunkHeader() {
        XCTAssertEqual(TBCodec.key(fromMessage: "TB1|profile:42|#2/5\nabc"), "profile:42")
        XCTAssertEqual(TBCodec.key(fromMessage: "TB1|profile:42"), "profile:42")
    }
}
