import XCTest
@testable import SiTVATV

final class PlayerRouterTests: XCTestCase {
    private let router = PlayerRouter()

    func testHLSUsesAVPlayerThenVLC() {
        let source = StreamSource(url: "https://example.com/live.m3u8", manifestType: "hls")
        XCTAssertEqual(router.engines(for: source), [.avPlayer, .vlc])
    }

    func testDASHUsesDASHEngineThenVLCWhenUnencrypted() {
        let source = StreamSource(url: "https://example.com/live.mpd", manifestType: "mpd")
        XCTAssertEqual(router.engines(for: source), [.dash, .vlc])
    }

    func testClearKeyDASHUsesOnlyClearKeyEngine() {
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd",
            drmType: "org.w3.clearkey",
            drmKey: "kid:key"
        )
        XCTAssertEqual(router.engines(for: source), [.dashClearKey])
    }

    func testWidevineIsUnsupportedOnNativeTVOSRoute() {
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd",
            drmType: "com.widevine.alpha"
        )
        XCTAssertTrue(router.engines(for: source).isEmpty)
    }

    func testAttemptsPreserveSourceOrder() {
        let channel = Channel(
            id: "demo",
            name: "Demo",
            group: "Test",
            logoURL: nil,
            sources: [
                StreamSource(url: "https://example.com/one.m3u8", manifestType: "hls"),
                StreamSource(url: "https://example.com/two.mpd", manifestType: "mpd")
            ]
        )

        let attempts = router.attempts(for: channel)
        XCTAssertEqual(attempts.map(\.sourceIndex), [0, 0, 1, 1])
        XCTAssertEqual(attempts.map(\.engine), [.avPlayer, .vlc, .dash, .vlc])
    }
}
