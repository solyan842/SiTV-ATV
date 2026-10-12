import CMAFKit
import Foundation
import XCTest
@testable import SiTVATV

final class DASHClearKeySessionTests: XCTestCase {
    func testPrepareLoadsManifestAndInitAndMatchesKeyID() async throws {
        let kid = Data((0..<16).map(UInt8.init))
        let key = Data((16..<32).map(UInt8.init))
        let baseURL = URL(string: "https://example.com/live/")!
        let initURL = URL(string: "https://example.com/live/init-video.mp4")!

        let template = DASHSegmentTemplate(
            initialization: "init-$RepresentationID$.mp4",
            media: "$Number$.m4s",
            timescale: 1,
            duration: 2,
            startNumber: 1,
            presentationTimeOffset: 0,
            timeline: []
        )
        let representation = DASHRepresentation(
            id: "video",
            bandwidth: 2_000_000,
            width: 1920,
            height: 1080,
            mimeType: "video/mp4",
            codecs: "avc1.640028",
            baseURL: baseURL,
            segmentTemplate: template,
            contentProtections: []
        )
        let adaptation = DASHAdaptationSet(
            id: "v",
            mimeType: "video/mp4",
            contentType: "video",
            codecs: nil,
            language: nil,
            baseURL: baseURL,
            segmentTemplate: template,
            contentProtections: [],
            representations: [representation]
        )
        let manifest = DASHManifest(
            type: .static,
            minimumUpdatePeriod: nil,
            baseURL: baseURL,
            periods: [
                DASHPeriod(id: "p0", baseURL: baseURL, adaptationSets: [adaptation])
            ]
        )
        let source = StreamSource(
            url: "https://example.com/live/manifest.mpd",
            manifestType: "mpd",
            drmType: "clearkey",
            drmKey: "000102030405060708090a0b0c0d0e0f:101112131415161718191a1b1c1d1e1f"
        )
        let track = CENCTrackInfo(
            trackID: 1,
            kind: .video,
            scheme: .cenc,
            keyID: kid,
            perSampleIVSize: 8,
            constantIV: nil,
            cryptByteBlock: 0,
            skipByteBlock: 0
        )
        let loader = FakeResourceLoader(
            manifest: manifest,
            dataByURL: [initURL: Data([0x01, 0x02])]
        )
        let session = DASHClearKeySession(
            loader: loader,
            inspector: FakeInspector(inspection: CENCInspection(tracks: [track]))
        )

        let prepared = try await session.prepare(source: source, segmentCount: 2)

        XCTAssertEqual(prepared.keyMaterial.keyID, kid)
        XCTAssertEqual(prepared.keyMaterial.key, key)
        XCTAssertEqual(prepared.video?.plan.initializationURL, initURL)
        XCTAssertEqual(prepared.video?.plan.mediaSegments.count, 2)
        XCTAssertEqual(prepared.video?.encryption, track)
        XCTAssertNil(prepared.audio)
    }

    func testPrepareRejectsKeyIDNotPresentInSelectedTrack() async throws {
        let baseURL = URL(string: "https://example.com/live/")!
        let template = DASHSegmentTemplate(
            initialization: "init.mp4",
            media: "$Number$.m4s",
            timescale: 1,
            duration: 2,
            startNumber: 1,
            presentationTimeOffset: 0,
            timeline: []
        )
        let representation = DASHRepresentation(
            id: "video",
            bandwidth: 1,
            width: nil,
            height: nil,
            mimeType: "video/mp4",
            codecs: nil,
            baseURL: baseURL,
            segmentTemplate: template,
            contentProtections: []
        )
        let manifest = DASHManifest(
            type: .static,
            minimumUpdatePeriod: nil,
            baseURL: baseURL,
            periods: [
                DASHPeriod(
                    id: nil,
                    baseURL: baseURL,
                    adaptationSets: [
                        DASHAdaptationSet(
                            id: nil,
                            mimeType: "video/mp4",
                            contentType: "video",
                            codecs: nil,
                            language: nil,
                            baseURL: baseURL,
                            segmentTemplate: template,
                            contentProtections: [],
                            representations: [representation]
                        )
                    ]
                )
            ]
        )
        let source = StreamSource(
            url: "https://example.com/live/manifest.mpd",
            drmType: "clearkey",
            drmKey: "000102030405060708090a0b0c0d0e0f:101112131415161718191a1b1c1d1e1f"
        )
        let otherKID = Data(repeating: 0xff, count: 16)
        let track = CENCTrackInfo(
            trackID: 1,
            kind: .video,
            scheme: .cenc,
            keyID: otherKID,
            perSampleIVSize: 8,
            constantIV: nil,
            cryptByteBlock: 0,
            skipByteBlock: 0
        )
        let initURL = URL(string: "https://example.com/live/init.mp4")!
        let session = DASHClearKeySession(
            loader: FakeResourceLoader(manifest: manifest, dataByURL: [initURL: Data([0x00])]),
            inspector: FakeInspector(inspection: CENCInspection(tracks: [track]))
        )

        do {
            _ = try await session.prepare(source: source)
            XCTFail("Expected key ID mismatch")
        } catch let error as DASHClearKeySessionError {
            XCTAssertEqual(error, .keyIDNotPresentInSelectedTracks)
        }
    }
}

private struct FakeResourceLoader: DASHResourceLoading {
    let manifest: DASHManifest
    let dataByURL: [URL: Data]

    func loadManifest(from url: URL, headers: [String: String]) async throws -> DASHManifest {
        manifest
    }

    func loadData(from url: URL, headers: [String: String]) async throws -> Data {
        guard let data = dataByURL[url] else {
            throw DASHResourceLoaderError.httpStatus(404)
        }
        return data
    }
}

private struct FakeInspector: CENCInspecting {
    let inspection: CENCInspection

    func inspect(initSegment data: Data) async throws -> CENCInspection {
        inspection
    }
}
