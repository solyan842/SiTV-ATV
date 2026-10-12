import CMAFKit
import XCTest
@testable import SiTVATV

final class DASHClearKeyMediaSessionTests: XCTestCase {
    func testProcessesVideoAndAudioPipelines() async throws {
        let video = MediaSessionPipeline(segments: [makeSegment(index: 1)])
        let audio = MediaSessionPipeline(segments: [makeSegment(index: 2), makeSegment(index: 3)])
        let session = DASHClearKeyMediaSession(
            videoPipeline: video,
            audioPipeline: audio
        )

        let output = try await session.processPlannedSegments()

        XCTAssertEqual(output.video.map(\.segmentIndex), [1])
        XCTAssertEqual(output.audio.map(\.segmentIndex), [2, 3])
        XCTAssertFalse(output.isEmpty)
        XCTAssertEqual(await video.processCount(), 1)
        XCTAssertEqual(await audio.processCount(), 1)
    }

    func testMissingTrackProducesEmptySide() async throws {
        let audio = MediaSessionPipeline(segments: [makeSegment(index: 4)])
        let session = DASHClearKeyMediaSession(
            videoPipeline: nil,
            audioPipeline: audio
        )

        let output = try await session.processPlannedSegments()

        XCTAssertTrue(output.video.isEmpty)
        XCTAssertEqual(output.audio.map(\.segmentIndex), [4])
    }

    func testFinalizeAttemptsBothPipelinesAndReturnsFirstError() async throws {
        let video = MediaSessionPipeline(
            segments: [],
            finalizeError: MediaSessionTestError.videoFinalize
        )
        let audio = MediaSessionPipeline(
            segments: [],
            finalizeError: MediaSessionTestError.audioFinalize
        )
        let session = DASHClearKeyMediaSession(
            videoPipeline: video,
            audioPipeline: audio
        )

        do {
            try await session.finalize()
            XCTFail("Expected finalize failure")
        } catch {
            XCTAssertEqual(error as? MediaSessionTestError, .videoFinalize)
        }

        XCTAssertEqual(await video.finalizeCount(), 1)
        XCTAssertEqual(await audio.finalizeCount(), 1)
    }

    private func makeSegment(index: Int) -> ParsedMediaSegment {
        ParsedMediaSegment(
            segmentIndex: index,
            samples: [],
            movieFragmentSequenceNumbers: [],
            baseMediaDecodeTimes: [:],
            hasSegmentIndex: false,
            hasProducerReferenceTime: false,
            eventMessages: [],
            segmentIndices: [],
            isChunkedSegment: false,
            firstSampleIsSyncSample: true
        )
    }
}

private actor MediaSessionPipeline: DASHClearKeyTrackProcessing {
    private let segments: [ParsedMediaSegment]
    private let finalizeError: MediaSessionTestError?
    private var processCalls = 0
    private var finalizeCalls = 0

    init(
        segments: [ParsedMediaSegment],
        finalizeError: MediaSessionTestError? = nil
    ) {
        self.segments = segments
        self.finalizeError = finalizeError
    }

    func processPlannedSegments() async throws -> [ParsedMediaSegment] {
        processCalls += 1
        return segments
    }

    func finalize() async throws {
        finalizeCalls += 1
        if let finalizeError {
            throw finalizeError
        }
    }

    func processCount() -> Int {
        processCalls
    }

    func finalizeCount() -> Int {
        finalizeCalls
    }
}

private enum MediaSessionTestError: Error, Equatable {
    case videoFinalize
    case audioFinalize
}
