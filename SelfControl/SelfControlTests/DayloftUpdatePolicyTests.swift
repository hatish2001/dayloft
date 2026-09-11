import XCTest
final class DayloftUpdatePolicyTests: XCTestCase {
    private let key = Data(repeating: 7, count: 32).base64EncodedString()
    func testOnlyConfiguredHTTPSFeedCanStartUpdater() {
        XCTAssertTrue(DayloftUpdatePolicy.isConfigured(feed: "https://github.com/hatish2001/dayloft/releases/latest/download/appcast.xml", publicKey: key))
        for feed in ["", "$(DAYLOFT_UPDATE_FEED_URL)", "http://updates.test/feed.xml", "https://name:password@updates.test/feed.xml", "https://example.com/feed.xml", "https://127.0.0.1/feed.xml"] {
            XCTAssertFalse(DayloftUpdatePolicy.isConfigured(feed: feed, publicKey: key))
        }
    }
    func testMissingOrInvalidSigningKeyDisablesUpdates() {
        for key in ["", "invalid", Data(repeating: 0, count: 32).base64EncodedString(), Data(repeating: 7, count: 31).base64EncodedString()] {
            XCTAssertFalse(DayloftUpdatePolicy.isConfigured(feed: "https://updates.test/feed.xml", publicKey: key))
        }
    }
    func testUpdateActionWaitsForActiveFocusAndPendingChanges() {
        XCTAssertTrue(DayloftUpdatePolicy.canRequestUpdate(configured: true, canCheck: true, focusActive: false, busy: false))
        for values in [(false,true,false,false), (true,false,false,false), (true,true,true,false), (true,true,false,true)] {
            XCTAssertFalse(DayloftUpdatePolicy.canRequestUpdate(configured: values.0, canCheck: values.1, focusActive: values.2, busy: values.3))
        }
    }
}
