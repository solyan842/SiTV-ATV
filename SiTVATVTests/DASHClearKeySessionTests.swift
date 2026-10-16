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
        let initData = minimalInitSegment(marker: 1)

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
            dataByURL: [initURL: initData]
        )
        let session = DASHClearKeySession(
            loader: loader,
            inspector: FakeInspector(inspection: CENCInspection(tracks: [track]))
        )

        let prepared = try await session.prepare(source: source, segmentCount: 2)

        XCTAssertEqual(prepared.keyMaterial.keyID, kid)
        XCTAssertEqual(prepared.keyMaterial.key, key)
        XCTAssertEqual(prepared.video?.keyMaterial?.keyID, kid)
        XCTAssertEqual(prepared.video?.plan.initializationURL, initURL)
        XCTAssertEqual(prepared.video?.plan.mediaSegments.count, 2)
        XCTAssertEqual(prepared.video?.encryption, track)
        XCTAssertNil(prepared.audio)
    }

    func testPrepareUsesDifferentClearKeysForVideoAndAudio() async throws {
        let videoKID = Data((0..<16).map(UInt8.init))
        let videoKey = Data((16..<32).map(UInt8.init))
        let audioKID = Data((32..<48).map(UInt8.init))
        let audioKey = Data((48..<64).map(UInt8.init))
        let baseURL = URL(string: "https://example.com/live/")!
        let videoInitURL = baseURL.appendingPathComponent("init-video.mp4")
        let audioInitURL = baseURL.appendingPathComponent("init-audio.mp4")
        let videoInitData = minimalInitSegment(marker: 1)
        let audioInitData = minimalInitSegment(marker: 2)

        let videoTemplate = DASHSegmentTemplate(
            initialization: "init-video.mp4",
            media: "video-$Number$.m4s",
            timescale: 1,
            duration: 2,
            startNumber: 1,
            presentationTimeOffset: 0,
            timeline: []
        )
        let audioTemplate = DASHSegmentTemplate(
            initialization: "init-audio.mp4",
            media: "audio-$Number$.m4s",
            timescale: 1,
            duration: 2,
            startNumber: 1,
            presentationTimeOffset: 0,
            timeline: []
        )
        let videoRepresentation = DASHRepresentation(
            id: "video",
            bandwidth: 2_000_000,
            width: 1920,
            height: 1080,
            mimeType: "video/mp4",
            codecs: "avc1.640028",
            baseURL: baseURL,
            segmentTemplate: videoTemplate,
            contentProtections: []
        )
        let audioRepresentation = DASHRepresentation(
            id: "audio",
            bandwidth: 128_000,
            width: nil,
            height: nil,
            mimeType: "audio/mp4",
            codecs: "mp4a.40.2",
            baseURL: baseURL,
            segmentTemplate: audioTemplate,
            contentProtections: []
        )
        let manifest = DASHManifest(
            type: .static,
            minimumUpdatePeriod: nil,
            baseURL: baseURL,
            periods: [
                DASHPeriod(
                    id: "p0",
                    baseURL: baseURL,
                    adaptationSets: [
                        DASHAdaptationSet(
                            id: "v",
                            mimeType: "video/mp4",
                            contentType: "video",
                            codecs: nil,
                            language: nil,
                            baseURL: baseURL,
                            segmentTemplate: videoTemplate,
                            contentProtections: [],
                            representations: [videoRepresentation]
                        ),
                        DASHAdaptationSet(
                            id: "a",
                            mimeType: "audio/mp4",
                            contentType: "audio",
                            codecs: nil,
                            language: nil,
                            baseURL: baseURL,
                            segmentTemplate: audioTemplate,
                            contentProtections: [],
                            representations: [audioRepresentation]
                        )
                    ]
                )
            ]
        )
        let videoTrack = CENCTrackInfo(
            trackID: 1,
            kind: .video,
            scheme: .cenc,
            keyID: videoKID,
            perSampleIVSize: 8,
            constantIV: nil,
            cryptByteBlock: 0,
            skipByteBlock: 0
        )
        let audioTrack = CENCTrackInfo(
            trackID: 2,
            kind: .audio,
            scheme: .cenc,
            keyID: audioKID,
            perSampleIVSize: 8,
            constantIV: nil,
            cryptByteBlock: 0,
            skipByteBlock: 0
        )
        let source = StreamSource(
            url: "https://example.com/live/manifest.mpd",
            manifestType: "mpd",
            drmType: "clearkey",
            drmKey: "\(hex(videoKID)):\(hex(videoKey)),\(hex(audioKID)):\(hex(audioKey))"
        )
        let session = DASHClearKeySession(
            loader: FakeResourceLoader(
                manifest: manifest,
                dataByURL: [
                    videoInitURL: videoInitData,
                    audioInitURL: audioInitData
                ]
            ),
            inspector: MappingInspector(
                inspections: [
                    videoInitData: CENCInspection(tracks: [videoTrack]),
                    audioInitData: CENCInspection(tracks: [audioTrack])
                ]
            )
        )

        let prepared = try await session.prepare(source: source, segmentCount: 2)

        XCTAssertEqual(prepared.video?.encryption.keyID, videoKID)
        XCTAssertEqual(prepared.video?.keyMaterial, ClearKeyMaterial(keyID: videoKID, key: videoKey))
        XCTAssertEqual(prepared.audio?.encryption.keyID, audioKID)
        XCTAssertEqual(prepared.audio?.keyMaterial, ClearKeyMaterial(keyID: audioKID, key: audioKey))
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
        let initData = minimalInitSegment(marker: 3)
        let session = DASHClearKeySession(
            loader: FakeResourceLoader(manifest: manifest, dataByURL: [initURL: initData]),
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

private struct MappingInspector: CENCInspecting {
    let inspections: [Data: CENCInspection]

    func inspect(initSegment data: Data) async throws -> CENCInspection {
        guard let inspection = inspections[data] else {
            throw DASHISOBMFFValidationError.invalidInitializationSegment(bytes: data.count)
        }
        return inspection
    }
}

private func minimalInitSegment(marker: UInt8) -> Data {
    Data([0x00, 0x00, 0x00, 0x09, 0x6d, 0x6f, 0x6f, 0x76, marker])
}

private func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}
