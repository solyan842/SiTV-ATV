import CoreMedia
import XCTest
@testable import SiTVATV

@MainActor
final class DASHSynchronizedRendererTests: XCTestCase {
    func testStartsAndPausesSharedTimeline() {
        let renderer = DASHSynchronizedRenderer()

        XCTAssertEqual(renderer.rate, 0)
        renderer.start(at: CMTime(value: 3, timescale: 2))
        XCTAssertEqual(renderer.rate, 1)
        renderer.pause()
        XCTAssertEqual(renderer.rate, 0)
    }

    func testDisplayLayerIsConfiguredForAspectFit() {
        let renderer = DASHSynchronizedRenderer()
        XCTAssertEqual(renderer.displayLayer.videoGravity, .resizeAspect)
    }
}
