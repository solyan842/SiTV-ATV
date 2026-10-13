import XCTest
@testable import SiTVATV

final class PlayerCoordinatorTests: XCTestCase {
    func testFallsBackToNextEngineForSameSource() async throws {
        let avPlayer = StubPlayerEngine(
            kind: .avPlayer,
            failingURLs: ["https://example.com/live.m3u8"]
        )
        let vlc = StubPlayerEngine(kind: .vlc)
        let coordinator = PlayerCoordinator(engines: [avPlayer, vlc])
        let channel = makeChannel(
            sources: [
                StreamSource(
                    url: "https://example.com/live.m3u8",
                    manifestType: "hls"
                )
            ]
        )

        let attempt = try await coordinator.play(channel)

        XCTAssertEqual(attempt.engine, .vlc)
        XCTAssertEqual(attempt.sourceIndex, 0)
        XCTAssertEqual(avPlayer.startedURLs, ["https://example.com/live.m3u8"])
        XCTAssertEqual(avPlayer.stopCount, 1)
        XCTAssertEqual(vlc.startedURLs, ["https://example.com/live.m3u8"])
        XCTAssertEqual(vlc.stopCount, 0)
    }

    func testFallsBackFromFailedSourceOneToSourceTwo() async throws {
        let engine = StubPlayerEngine(
            kind: .avPlayer,
            failingURLs: ["https://example.com/one.m3u8"]
        )
        let coordinator = PlayerCoordinator(engines: [engine])
        let channel = makeChannel(
            sources: [
                StreamSource(
                    url: "https://example.com/one.m3u8",
                    manifestType: "hls"
                ),
                StreamSource(
                    url: "https://example.com/two.m3u8",
                    manifestType: "hls"
                )
            ]
        )

        let attempt = try await coordinator.play(channel)

        XCTAssertEqual(attempt.engine, .avPlayer)
        XCTAssertEqual(attempt.sourceIndex, 1)
        XCTAssertEqual(
            engine.startedURLs,
            ["https://example.com/one.m3u8", "https://example.com/two.m3u8"]
        )
        XCTAssertEqual(engine.stopCount, 1)
    }

    func testPlayingAnotherChannelStopsCurrentEngineFirst() async throws {
        let engine = StubPlayerEngine(kind: .avPlayer)
        let coordinator = PlayerCoordinator(engines: [engine])
        let first = makeChannel(
            id: "first",
            sources: [StreamSource(url: "https://example.com/one.m3u8", manifestType: "hls")]
        )
        let second = makeChannel(
            id: "second",
            sources: [StreamSource(url: "https://example.com/two.m3u8", manifestType: "hls")]
        )

        _ = try await coordinator.play(first)
        _ = try await coordinator.play(second)

        XCTAssertEqual(
            engine.startedURLs,
            ["https://example.com/one.m3u8", "https://example.com/two.m3u8"]
        )
        XCTAssertEqual(engine.stopCount, 1)
    }

    func testThrowsUnsupportedWhenNoRegisteredEngineCanHandleAttempts() async {
        let coordinator = PlayerCoordinator(engines: [])
        let channel = makeChannel(
            sources: [
                StreamSource(
                    url: "https://example.com/live.m3u8",
                    manifestType: "hls"
                )
            ]
        )

        do {
            _ = try await coordinator.play(channel)
            XCTFail("Expected unsupported error")
        } catch let error as PlayerEngineError {
            XCTAssertEqual(error, .unsupported)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeChannel(
        id: String = "demo",
        sources: [StreamSource]
    ) -> Channel {
        Channel(
            id: id,
            name: id,
            group: "Test",
            logoURL: nil,
            sources: sources
        )
    }
}

private final class StubPlayerEngine: PlayerEngine {
    let kind: PlayerEngineKind
    let supported: Bool
    private let failingURLs: Set<String>

    private(set) var startedURLs: [String] = []
    private(set) var stopCount = 0

    init(
        kind: PlayerEngineKind,
        supported: Bool = true,
        failingURLs: Set<String> = []
    ) {
        self.kind = kind
        self.supported = supported
        self.failingURLs = failingURLs
    }

    func canPlay(_ source: StreamSource) -> Bool {
        supported
    }

    func start(_ request: PlaybackRequest) async throws {
        startedURLs.append(request.source.url)
        if failingURLs.contains(request.source.url) {
            throw PlayerEngineError.failedToStart("stub failure")
        }
    }

    func stop() async {
        stopCount += 1
    }
}
