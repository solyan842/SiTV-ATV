import XCTest
@testable import SiTVATV

final class VLCPlayerEngineTests: XCTestCase {
    func testPlainHLSIsSupported() {
        let engine = VLCPlayerEngine()
        XCTAssertTrue(engine.canPlay(StreamSource(url: "https://example.com/live.m3u8")))
    }

    func testPlainDASHIsSupported() {
        let engine = VLCPlayerEngine()
        XCTAssertTrue(engine.canPlay(StreamSource(url: "https://example.com/live.mpd", manifestType: "mpd")))
    }

    func testRefererAndUserAgentHeadersAreSupported() {
        let engine = VLCPlayerEngine()
        let source = StreamSource(
            url: "https://example.com/live.m3u8",
            headers: [
                "Referer": "https://example.com/",
                "User-Agent": "SiTV"
            ]
        )
        XCTAssertTrue(engine.canPlay(source))
    }

    func testArbitraryHTTPHeaderIsNotClaimedSupported() {
        let engine = VLCPlayerEngine()
        let source = StreamSource(
            url: "https://example.com/live.m3u8",
            headers: ["Authorization": "Bearer demo"]
        )
        XCTAssertFalse(engine.canPlay(source))
    }

    func testDRMIsNotClaimedSupported() {
        let engine = VLCPlayerEngine()
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd",
            drmType: "org.w3.clearkey",
            drmKey: "kid:key"
        )
        XCTAssertFalse(engine.canPlay(source))
    }
}
