import CMAFKit
import XCTest
@testable import SiTVATV

final class DASHClearKeyTrackPipelineTests: XCTestCase {
    func testProcessesPlannedSegmentsInOrderWithHeaders() async throws {
        let firstURL = URL(string: "https://example.com/seg-1.m4s")!
        let secondURL = URL(string: "https://example.com/seg-2.m4s")!
        let loader = TrackPipelineLoader(
            payloads: [
                firstURL: Data([0x01]),
                secondURL: Data([0x02])
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
        XCTAssertEqual(await processor.payloads(), [Data([0x01]), Data([0x02])])
        let requests = await loader.requests()
        XCTAssertEqual(requests.map(\.url), [firstURL, secondURL])
        XCTAssertEqual(requests.map(\.headers), [headers, headers])

        try await pipeline.finalize()
        XCTAssertTrue(await processor.wasFinalized())
    }

    func testRejectsOutOfRangeSegmentIndexBeforeLoading() async throws {
        let url = URL(string: "https://example.com/seg-1.m4s")!
        let loader = TrackPipelineLoader(payloads: [url: Data([0x01])])
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
        XCTAssertTrue(await loader.requests().isEmpty)
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
        return ParsedMediaSegment(
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

private enum TrackPipelineTestError: Error {
    case unusedManifestLoad
    case missingPayload
}
