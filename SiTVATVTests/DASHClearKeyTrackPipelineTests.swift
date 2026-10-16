import CMAFKit
import XCTest
@testable import SiTVATV

final class DASHClearKeyTrackPipelineTests: XCTestCase {
    func testProcessesPlannedSegmentsInOrderWithHeaders() async throws {
        let firstURL = URL(string: "https://example.com/seg-1.m4s")!
        let secondURL = URL(string: "https://example.com/seg-2.m4s")!
        let firstData = minimalMediaSegment(marker: 0x01)
        let secondData = minimalMediaSegment(marker: 0x02)
        let loader = TrackPipelineLoader(
            payloads: [
                firstURL: firstData,
                secondURL: secondData
            ]
        )
        let processor = TrackPipelineProcessor()
        let headers = ["Referer": "https://example.com/"]
        let pipeline = DASHClearKeyTrackPipeline(
            plan: makePlan(urls: [firstURL, secondURL]),
            headers: headers,
            loader: loader,
            processor: processor
        )

        let results = try await pipeline.processPlannedSegments()

        XCTAssertEqual(results.map(\.segmentIndex), [0, 1])
        let payloads = await processor.payloads()
        XCTAssertEqual(payloads, [firstData, secondData])
        let requests = await loader.requests()
        XCTAssertEqual(requests.map(\.url), [firstURL, secondURL])
        XCTAssertEqual(requests.map(\.headers), [headers, headers])

        try await pipeline.finalize()
        let finalized = await processor.wasFinalized()
        XCTAssertTrue(finalized)
    }

    func testProcessesRefreshedSegmentOutsideInitialPlan() async throws {
        let plannedURL = URL(string: "https://example.com/seg-1.m4s")!
        let refreshedURL = URL(string: "https://example.com/seg-7.m4s")!
        let headers = ["User-Agent": "SiTV"]
        let plannedData = minimalMediaSegment(marker: 0x01)
        let refreshedData = minimalMediaSegment(marker: 0x07)
        let loader = TrackPipelineLoader(
            payloads: [
                plannedURL: plannedData,
                refreshedURL: refreshedData
            ]
        )
        let processor = TrackPipelineProcessor()
        let pipeline = DASHClearKeyTrackPipeline(
            plan: makePlan(urls: [plannedURL]),
            headers: headers,
            loader: loader,
            processor: processor
        )
        let refreshedSegment = DASHResolvedSegment(
            number: 7,
            time: 18_000,
            duration: 3_000,
            url: refreshedURL
        )

        let result = try await pipeline.process(segment: refreshedSegment)

        XCTAssertEqual(result.segmentIndex, 0)
        let payloads = await processor.payloads()
        XCTAssertEqual(payloads, [refreshedData])
        let requests = await loader.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url, refreshedURL)
        XCTAssertEqual(requests.first?.headers, headers)
    }

    func testRetriesSameSegmentAfterInsufficientDataWithoutPoisoningPlayback() async throws {
        let url = URL(string: "https://example.com/live-42.m4s")!
        let validData = minimalMediaSegment(marker: 0x2A)
        let loader = TrackPipelineLoader(payloads: [url: validData])
        let processor = RetryTrackPipelineProcessor()
        let pipeline = DASHClearKeyTrackPipeline(
            plan: makePlan(urls: [url]),
            headers: [:],
            loader: loader,
            processor: processor,
            incompleteSegmentRetryCount: 1
        )

        let result = try await pipeline.processSegment(at: 0)
        let attempts = await processor.attemptCount()
        let requests = await loader.requests()

        XCTAssertEqual(result.segmentIndex, 0)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(requests.count, 2)
    }

    func testInvalid74ByteHTTPBodyNeverReachesCMAFProcessor() async throws {
        let url = URL(string: "https://example.com/live-42.m4s")!
        let badBody = Data(repeating: 0x41, count: 74)
        let loader = TrackPipelineLoader(payloads: [url: badBody])
        let processor = TrackPipelineProcessor()
        let pipeline = DASHClearKeyTrackPipeline(
            plan: makePlan(urls: [url]),
            headers: [:],
            loader: loader,
            processor: processor,
            incompleteSegmentRetryCount: 1
        )

        do {
            _ = try await pipeline.processSegment(at: 0)
            XCTFail("Expected invalid media response")
        } catch {
            XCTAssertEqual(
                error as? DASHISOBMFFValidationError,
                .invalidMediaSegment(bytes: 74)
            )
        }

        let requests = await loader.requests()
        let payloads = await processor.payloads()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(payloads.isEmpty)
    }

    func testRejectsOutOfRangeSegmentIndexBeforeLoading() async throws {
        let url = URL(string: "https://example.com/seg-1.m4s")!
        let loader = TrackPipelineLoader(payloads: [url: minimalMediaSegment(marker: 0x01)])
        let pipeline = DASHClearKeyTrackPipeline(
            plan: makePlan(urls: [url]),
            headers: [:],
            loader: loader,
            processor: TrackPipelineProcessor()
        )

        do {
            _ = try await pipeline.processSegment(at: 3)
            XCTFail("Expected segmentIndexOutOfRange")
        } catch {
            XCTAssertEqual(
                error as? DASHClearKeyTrackPipelineError,
                .segmentIndexOutOfRange(3)
            )
        }
        let requests = await loader.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    private func makePlan(urls: [URL]) -> DASHTrackPlan {
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
        let segments = urls.enumerated().map { index, url in
            DASHResolvedSegment(
                number: UInt64(index + 1),
                time: UInt64(index * 3_000),
                duration: 3_000,
                url: url
            )
        }
        return DASHTrackPlan(
            representation: representation,
            initializationURL: baseURL.appendingPathComponent("init.mp4"),
            mediaSegments: segments
        )
    }
}

private actor TrackPipelineLoader: DASHResourceLoading {
    struct Request: Equatable {
        let url: URL
        let headers: [String: String]
    }

    private let payloads: [URL: Data]
    private var recordedRequests: [Request] = []

    init(payloads: [URL: Data]) {
        self.payloads = payloads
    }

    func loadManifest(
        from url: URL,
        headers: [String: String]
    ) async throws -> DASHManifest {
        throw TrackPipelineTestError.unusedManifestLoad
    }

    func loadData(
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        recordedRequests.append(Request(url: url, headers: headers))
        guard let data = payloads[url] else {
            throw TrackPipelineTestError.missingPayload
        }
        return data
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

private actor TrackPipelineProcessor: DASHClearKeyMediaProcessing {
    private var received: [Data] = []
    private var finalized = false

    func process(segmentData: Data) async throws -> ParsedMediaSegment {
        let index = received.count
        received.append(segmentData)
        return makeParsedMediaSegment(index: index)
    }

    func finalize() async throws {
        finalized = true
    }

    func payloads() -> [Data] {
        received
    }

    func wasFinalized() -> Bool {
        finalized
    }
}

private actor RetryTrackPipelineProcessor: DASHClearKeyMediaProcessing {
    private var attempts = 0

    func process(segmentData: Data) async throws -> ParsedMediaSegment {
        attempts += 1
        if attempts == 1 {
            throw BinaryIOError.insufficientData(expected: 29_545, available: 74)
        }
        return makeParsedMediaSegment(index: 0)
    }

    func finalize() async throws {}

    func attemptCount() -> Int {
        attempts
    }
}

private func makeParsedMediaSegment(index: Int) -> ParsedMediaSegment {
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

private func minimalMediaSegment(marker: UInt8) -> Data {
    Data([
        0x00, 0x00, 0x00, 0x09, 0x6d, 0x6f, 0x6f, 0x66, marker,
        0x00, 0x00, 0x00, 0x08, 0x6d, 0x64, 0x61, 0x74
    ])
}

private enum TrackPipelineTestError: Error {
    case unusedManifestLoad
    case missingPayload
}
