import XCTest
@testable import SiTVATV

final class AVPlayerEngineTests: XCTestCase {
    func testPlainHLSIsSupported() {
        let engine = AVPlayerEngine()
        let source = StreamSource(
            url: "https://example.com/live.m3u8",
            manifestType: "hls"
        )
        XCTAssertTrue(engine.canPlay(source))
    }

    func testDASHIsNotSupported() {
        let engine = AVPlayerEngine()
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd"
        )
        XCTAssertFalse(engine.canPlay(source))
    }

    func testClearKeyIsNotSupported() {
        let engine = AVPlayerEngine()
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd",
            drmType: "clearkey",
            drmKey: "kid:key"
        )
        XCTAssertFalse(engine.canPlay(source))
    }

    func testCustomHTTPHeadersAreNotForcedThroughAVPlayer() {
        let engine = AVPlayerEngine()
        let source = StreamSource(
            url: "https://example.com/live.m3u8",
            headers: ["Referer": "https://example.com/"]
        )
        XCTAssertFalse(engine.canPlay(source))
    }
}
