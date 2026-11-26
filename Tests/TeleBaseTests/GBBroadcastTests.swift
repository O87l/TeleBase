import XCTest
@testable import TeleBase

final class TBBroadcastTests: XCTestCase {

    private let feedHTML = """
    <div class="tgme_widget_message_wrap">
      <div class="tgme_widget_message" data-post="mychannel/10">
        <div class="tgme_widget_message_text">Welcome &amp; hello<br>Second line</div>
        <time datetime="2026-11-20T10:00:00+00:00"></time>
      </div>
    </div>
    <div class="tgme_widget_message_wrap">
      <div class="tgme_widget_message" data-post="mychannel/11">
        <div class="tgme_widget_message_text">TBCFG
        {"announcement":"Hi there","minVersion":"1.2.0","featureFlags":{"snow":true}}</div>
        <time datetime="2026-11-21T10:00:00+00:00"></time>
      </div>
    </div>
    """

    func testParseFeed() {
        let messages = TBBroadcastClient.parseFeed(feedHTML)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].id, "mychannel/10")
        XCTAssertEqual(messages[0].text, "Welcome & hello\nSecond line")
        XCTAssertNotNil(messages[0].date)
    }

    func testConfigExtraction() {
        let messages = TBBroadcastClient.parseFeed(feedHTML)
        let config = TBBroadcastClient.config(from: messages)
        XCTAssertEqual(config?.announcement, "Hi there")
        XCTAssertEqual(config?.minVersion, "1.2.0")
        XCTAssertEqual(config?.flag("snow"), true)
        XCTAssertEqual(config?.flag("missing"), false)
    }

    func testNoConfigMessage() {
        let messages = [TBBroadcastMessage(id: "c/1", text: "just news", date: nil)]
        XCTAssertNil(TBBroadcastClient.config(from: messages))
    }
}
