import CMAFKit
import XCTest
@testable import SiTVATV

final class DASHPlaybackContextTests: XCTestCase {
    func testRejectsMissingTrackConfiguration() async throws {
        let trackID: UInt32 = 7
        let builder = DASHPlaybackContextBuilder(
            trackReader: StubInitTrackReader(configuredTracks: [])
        )
        let preparation = DASHClearKeyPreparation(
            manifest: makeManifest(),
            keyMaterial: ClearKeyMaterial(
                keyID: Data(repeating: 0x11, count: 16),
                key: Data(repeating: 0x22, count: 16)
            ),
            video: makePreparedTrack(trackID: trackID),
            audio: nil
        )

        do {
            _ = try await builder.make(preparation: preparation)
            XCTFail("Expected missingTrackConfiguration")
        } catch {
            XCTAssertEqual(
                error as? DASHPlaybackContextError,
                .missingTrackConfiguration(trackID)
            )
        }
    }

    private func makePreparedTrack(trackID: UInt32) -> DASHPreparedTrack {
        let baseURL = URL(string: "https://example.com/")!
        let representation = DASHRepresentation(
            id: "video",
            bandwidth: 1_000_000,
            width: 1280,
            height: 720,
            mimeType: "video/mp4",
            codecs: "avc1.64001f",
            baseURL: baseURL,
            segmentTemplate: nil,
            contentProtections: []
        )
        let plan = DASHTrackPlan(
            representation: representation,
            initializationURL: baseURL.appendingPathComponent("init.mp4"),
            mediaSegments: []
        )
        let encryption = CENCTrackInfo(
            trackID: trackID,
            kind: .video,
            scheme: .cenc,
            keyID: Data(repeating: 0x11, count: 16),
            perSampleIVSize: 16,
            constantIV: nil,
            cryptByteBlock: 0,
            skipByteBlock: 0
        )
        return DASHPreparedTrack(
            plan: plan,
            initializationData: Data([0x00]),
            encryption: encryption
        )
    }

    private func makeManifest() -> DASHManifest {
        let baseURL = URL(string: "https://example.com/")!
        return DASHManifest(
            type: .static,
            minimumUpdatePeriod: nil,
            baseURL: baseURL,
            periods: []
        )
    }
}

private struct StubInitTrackReader: DASHInitTrackReading {
    let configuredTracks: [CMAFTrackConfiguration]

    func tracks(from initializationData: Data) async throws -> [CMAFTrackConfiguration] {
        configuredTracks
    }
}
