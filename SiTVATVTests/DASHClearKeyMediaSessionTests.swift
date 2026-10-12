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
        let videoProcessCount = await video.processCount()
        let audioProcessCount = await audio.processCount()
        XCTAssertEqual(videoProcessCount, 1)
        XCTAssertEqual(audioProcessCount, 1)
    }

    func testProcessesRefreshedSegmentsOnMatchingPipelines() async throws {
        let video = MediaSessionPipeline(segments: [])
        let audio = MediaSessionPipeline(segments: [])
        let session = DASHClearKeyMediaSession(
            videoPipeline: video,
            audioPipeline: audio
        )

        let output = try await session.process(
            videoSegments: [makeResolvedSegment(number: 7, path: "v7.m4s")],
            audioSegments: [
                makeResolvedSegment(number: 11, path: "a11.m4s"),
                makeResolvedSegment(number: 12, path: "a12.m4s")
            ]
        )
        let videoRefreshedNumbers = await video.refreshedNumbers()
        let audioRefreshedNumbers = await audio.refreshedNumbers()

        XCTAssertEqual(output.video.map(\.segmentIndex), [7])
        XCTAssertEqual(output.audio.map(\.segmentIndex), [11, 12])
        XCTAssertEqual(videoRefreshedNumbers, [7])
        XCTAssertEqual(audioRefreshedNumbers, [11, 12])
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

        let videoFinalizeCount = await video.finalizeCount()
        let audioFinalizeCount = await audio.finalizeCount()
        XCTAssertEqual(videoFinalizeCount, 1)
        XCTAssertEqual(audioFinalizeCount, 1)
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

    private func makeResolvedSegment(
        number: UInt64,
        path: String
    ) -> DASHResolvedSegment {
        DASHResolvedSegment(
            number: number,
            time: number * 2_000,
            duration: 2_000,
            url: URL(string: "https://example.com/\(path)")!
        )
    }
}

private actor MediaSessionPipeline: DASHClearKeyTrackProcessing {
    private let segments: [ParsedMediaSegment]
    private let finalizeError: MediaSessionTestError?
    private var processCalls = 0
    private var finalizeCalls = 0
    private var refreshed: [UInt64] = []

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

    func process(segment: DASHResolvedSegment) async throws -> ParsedMediaSegment {
        refreshed.append(segment.number)
        return ParsedMediaSegment(
            segmentIndex: Int(segment.number),
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

    func finalize() async throws {
        finalizeCalls += 1
        if let finalizeError {
            throw finalizeError
        }
    }

    func processCount() -> Int {
        processCalls
    }

    func refreshedNumbers() -> [UInt64] {
        refreshed
    }

    func finalizeCount() -> Int {
        finalizeCalls
    }
}

private enum MediaSessionTestError: Error, Equatable {
    case videoFinalize
    case audioFinalize
}
