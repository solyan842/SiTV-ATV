import CMAFKit
import XCTest
@testable import SiTVATV

final class DASHClearKeyMediaSessionTests: XCTestCase {
    func testConsumesPlannedVideoAndAudioSegmentsInOrder() async throws {
        let videoSegments = [makeSegment(number: 1, path: "video-1.m4s"), makeSegment(number: 2, path: "video-2.m4s")]
        let audioSegments = [makeSegment(number: 10, path: "audio-10.m4s"), makeSegment(number: 11, path: "audio-11.m4s")]
        let videoTrack = makePreparedTrack(trackID: 1, kind: .video, segments: videoSegments)
        let audioTrack = makePreparedTrack(trackID: 2, kind: .audio, segments: audioSegments)
        let videoPipeline = StubTrackPipeline()
        let audioPipeline = StubTrackPipeline()
        let builder = StubTrackPipelineBuilder(video: videoPipeline, audio: audioPipeline)
        let preparation = makePreparation(video: videoTrack, audio: audioTrack)

        let session = try await DASHClearKeyMediaSession.make(
            preparation: preparation,
            headers: ["Referer": "https://example.com/"],
            builder: builder
        )
        let output = try await session.consumePlannedSegments()

        XCTAssertEqual(output.video.map(\.segment.number), [1, 2])
        XCTAssertEqual(output.audio.map(\.segment.number), [10, 11])
        let consumedVideo = await videoPipeline.consumedNumbers()
        let consumedAudio = await audioPipeline.consumedNumbers()
        XCTAssertEqual(consumedVideo, [1, 2])
        XCTAssertEqual(consumedAudio, [10, 11])

        try await session.finalize()
        let videoFinalized = await videoPipeline.isFinalized()
        let audioFinalized = await audioPipeline.isFinalized()
        XCTAssertTrue(videoFinalized)
        XCTAssertTrue(audioFinalized)
    }

    func testFinalizeStillClosesAudioWhenVideoFinalizeFails() async throws {
        let videoTrack = makePreparedTrack(
            trackID: 1,
            kind: .video,
            segments: [makeSegment(number: 1, path: "video-1.m4s")]
        )
        let audioTrack = makePreparedTrack(
            trackID: 2,
            kind: .audio,
            segments: [makeSegment(number: 2, path: "audio-2.m4s")]
        )
        let videoPipeline = StubTrackPipeline(finalizeError: StubSessionError.videoFinalize)
        let audioPipeline = StubTrackPipeline()
        let session = DASHClearKeyMediaSession(
            videoTrack: videoTrack,
            audioTrack: audioTrack,
            videoPipeline: videoPipeline,
            audioPipeline: audioPipeline
        )

        do {
            try await session.finalize()
            XCTFail("Expected video finalize error")
        } catch {
            XCTAssertEqual(error as? StubSessionError, .videoFinalize)
        }

        let videoFinalized = await videoPipeline.isFinalized()
        let audioFinalized = await audioPipeline.isFinalized()
        XCTAssertTrue(videoFinalized)
        XCTAssertTrue(audioFinalized)
    }

    private func makePreparation(
        video: DASHPreparedTrack?,
        audio: DASHPreparedTrack?
    ) -> DASHClearKeyPreparation {
        DASHClearKeyPreparation(
            manifest: DASHManifest(
                type: .static,
                minimumUpdatePeriod: nil,
                baseURL: URL(string: "https://example.com/")!,
                periods: []
            ),
            keyMaterial: ClearKeyMaterial(
                keyID: Data(repeating: 0x11, count: 16),
                key: Data(repeating: 0x22, count: 16)
            ),
            video: video,
            audio: audio
        )
    }

    private func makePreparedTrack(
        trackID: UInt32,
        kind: CMAFTrackKind,
        segments: [DASHResolvedSegment]
    ) -> DASHPreparedTrack {
        let representation = DASHRepresentation(
            id: "track-\(trackID)",
            bandwidth: 1_000_000,
            width: kind == .video ? 1920 : nil,
            height: kind == .video ? 1080 : nil,
            mimeType: kind == .video ? "video/mp4" : "audio/mp4",
            codecs: kind == .video ? "avc1.640028" : "mp4a.40.2",
            baseURL: URL(string: "https://example.com/")!,
            segmentTemplate: nil,
            contentProtections: []
        )
        return DASHPreparedTrack(
            plan: DASHTrackPlan(
                representation: representation,
                initializationURL: URL(string: "https://example.com/init-\(trackID).mp4")!,
                mediaSegments: segments
            ),
            initializationData: Data([0x00]),
            encryption: CENCTrackInfo(
                trackID: trackID,
                kind: kind,
                scheme: .cenc,
                keyID: Data(repeating: 0x11, count: 16),
                perSampleIVSize: 16,
                constantIV: nil,
                cryptByteBlock: 0,
                skipByteBlock: 0
            )
        )
    }

    private func makeSegment(number: UInt64, path: String) -> DASHResolvedSegment {
        DASHResolvedSegment(
            number: number,
            time: number * 1000,
            duration: 1000,
            url: URL(string: "https://example.com/\(path)")!
        )
    }
}

private actor StubTrackPipeline: DASHClearKeyTrackProcessing {
    private var consumed: [UInt64] = []
    private var finalized = false
    private let finalizeError: Error?

    init(finalizeError: Error? = nil) {
        self.finalizeError = finalizeError
    }

    func loadAndDecrypt(_ segment: DASHResolvedSegment) async throws -> DASHDecryptedMediaSegment {
        consumed.append(segment.number)
        return DASHDecryptedMediaSegment(segment: segment, samples: [])
    }

    func finalize() async throws {
        finalized = true
        if let finalizeError {
            throw finalizeError
        }
    }

    func consumedNumbers() -> [UInt64] {
        consumed
    }

    func isFinalized() -> Bool {
        finalized
    }
}

private actor StubTrackPipelineBuilder: DASHClearKeyTrackPipelineBuilding {
    private let video: StubTrackPipeline
    private let audio: StubTrackPipeline

    init(video: StubTrackPipeline, audio: StubTrackPipeline) {
        self.video = video
        self.audio = audio
    }

    func make(
        preparedTrack: DASHPreparedTrack,
        material: ClearKeyMaterial,
        headers: [String: String]
    ) async throws -> any DASHClearKeyTrackProcessing {
        switch preparedTrack.encryption.kind {
        case .video:
            return video
        case .audio:
            return audio
        default:
            throw StubSessionError.unsupportedTrack
        }
    }
}

private enum StubSessionError: Error, Equatable {
    case videoFinalize
    case unsupportedTrack
}
