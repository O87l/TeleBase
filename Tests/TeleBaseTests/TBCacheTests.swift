import XCTest
@testable import TeleBase

final class TBCacheTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TeleBaseCacheTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        super.tearDown()
    }

    func testStoreAndRead() {
        let cache = TBDiskCache(directory: directory, ttl: 60)
        XCTAssertNil(cache.string(forKey: "a"))
        cache.set("hello", forKey: "a")
        XCTAssertEqual(cache.string(forKey: "a"), "hello")
    }

    func testPersistenceAcrossInstances() {
        let first = TBDiskCache(directory: directory, ttl: 60)
        first.set("saved", forKey: "k")
        let second = TBDiskCache(directory: directory, ttl: 60)
        XCTAssertEqual(second.string(forKey: "k"), "saved")
    }

    func testExpiry() {
        var now = Date(timeIntervalSince1970: 1_000)
        let cache = TBDiskCache(directory: directory, ttl: 60, now: { now })
        cache.set("fresh", forKey: "k")
        XCTAssertEqual(cache.string(forKey: "k"), "fresh")

        now = now.addingTimeInterval(61)
        XCTAssertNil(cache.string(forKey: "k"))
    }

    func testRemove() {
        let cache = TBDiskCache(directory: directory, ttl: 60)
        cache.set("x", forKey: "k")
        cache.remove(forKey: "k")
        XCTAssertNil(cache.string(forKey: "k"))
    }
}
