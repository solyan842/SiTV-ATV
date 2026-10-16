import XCTest
@testable import SiTVATV

final class DASHSegmentBasePlannerTests: XCTestCase {
    func testBuildsMediaByteRangesFromSIDX() async throws {
        let representation = DASHRepresentation(
            id: "v1",
            bandwidth: 2_000_000,
            width: 1280,
            height: 720,
            mimeType: "video/mp4",
            codecs: "avc1.640028",
            baseURL: URL(string: "https://example.com/video.mp4")!,
            segmentTemplate: nil,
            segmentBase: DASHSegmentBase(
                indexRange: DASHByteRange(start: 100, end: 155),
                initializationRange: DASHByteRange(start: 0, end: 99)
            ),
            contentProtections: []
        )
        let adaptation = DASHAdaptationSet(
            id: "v",
            mimeType: "video/mp4",
            contentType: "video",
            codecs: "avc1.640028",
            language: nil,
            baseURL: representation.baseURL,
            segmentTemplate: nil,
            segmentBase: representation.segmentBase,
            contentProtections: [],
            representations: [representation]
        )
        let manifest = DASHManifest(
            type: .static,
            minimumUpdatePeriod: nil,
            baseURL: URL(string: "https://example.com/")!,
            periods: [DASHPeriod(
                id: "p0",
                baseURL: URL(string: "https://example.com/")!,
                adaptationSets: [adaptation]
            )]
        )
        let loader = SegmentBaseLoader(indexData: makeSIDX())
        let planner = DASHSegmentBasePlanner(loader: loader)

        let plan = try await planner.makePlan(
            from: manifest,
            headers: [:],
            segmentCount: 2
        )
        let video = try XCTUnwrap(plan.video)

        XCTAssertEqual(video.initializationRange, DASHByteRange(start: 0, end: 99))
        XCTAssertEqual(video.mediaSegments.count, 2)
        XCTAssertEqual(video.mediaSegments[0].byteRange, DASHByteRange(start: 156, end: 205))
        XCTAssertEqual(video.mediaSegments[0].duration, 2_000)
        XCTAssertEqual(video.mediaSegments[1].byteRange, DASHByteRange(start: 206, end: 265))
        XCTAssertEqual(video.mediaSegments[1].duration, 3_000)
        XCTAssertEqual(loader.requestedRanges, [DASHByteRange(start: 100, end: 155)])
    }

    func testRejectsUnsupportedVideoCodecBeforeRangeLoading() async {
        let representation = DASHRepresentation(
            id: "vp9",
            bandwidth: 9_000_000,
            width: 1920,
            height: 1080,
            mimeType: "video/webm",
            codecs: "vp09.00.40.08",
            baseURL: URL(string: "https://example.com/video.webm")!,
            segmentTemplate: nil,
            segmentBase: DASHSegmentBase(
                indexRange: DASHByteRange(start: 100, end: 155),
                initializationRange: DASHByteRange(start: 0, end: 99)
            ),
            contentProtections: []
        )
        let adaptation = DASHAdaptationSet(
            id: "v",
            mimeType: "video/webm",
            contentType: "video",
            codecs: nil,
            language: nil,
            baseURL: representation.baseURL,
            segmentTemplate: nil,
            segmentBase: representation.segmentBase,
            contentProtections: [],
            representations: [representation]
        )
        let manifest = DASHManifest(
            type: .static,
            minimumUpdatePeriod: nil,
            baseURL: URL(string: "https://example.com/")!,
            periods: [DASHPeriod(id: nil, baseURL: URL(string: "https://example.com/")!, adaptationSets: [adaptation])]
        )
        let loader = SegmentBaseLoader(indexData: makeSIDX())

        do {
            _ = try await DASHSegmentBasePlanner(loader: loader).makePlan(
                from: manifest,
                headers: [:]
            )
            XCTFail("Expected no playable representation")
        } catch {
            XCTAssertEqual(error as? DASHSegmentBasePlannerError, .noPlayableRepresentations)
            XCTAssertTrue(loader.requestedRanges.isEmpty)
        }
    }

    private func makeSIDX() -> Data {
        var data = Data()
        appendUInt32(56, to: &data)
        data.append(contentsOf: Array("sidx".utf8))
        data.append(contentsOf: [0, 0, 0, 0]) // version + flags
        appendUInt32(1, to: &data) // reference ID
        appendUInt32(1_000, to: &data)
        appendUInt32(0, to: &data) // earliest presentation time
        appendUInt32(0, to: &data) // first offset
        data.append(contentsOf: [0, 0])
        data.append(contentsOf: [0, 2]) // reference count
        appendUInt32(50, to: &data)
        appendUInt32(2_000, to: &data)
        appendUInt32(0x9000_0000, to: &data)
        appendUInt32(60, to: &data)
        appendUInt32(3_000, to: &data)
        appendUInt32(0x9000_0000, to: &data)
        return data
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }
}

private final class SegmentBaseLoader: DASHResourceLoading {
    let indexData: Data
    private(set) var requestedRanges: [DASHByteRange] = []

    init(indexData: Data) {
        self.indexData = indexData
    }

    func loadManifest(from url: URL, headers: [String: String]) async throws -> DASHManifest {
        throw DASHSegmentBasePlannerError.invalidSIDX
    }

    func loadData(from url: URL, headers: [String: String]) async throws -> Data {
        indexData
    }

    func loadData(
        from url: URL,
        headers: [String: String],
        byteRange: DASHByteRange?
    ) async throws -> Data {
        if let byteRange {
            requestedRanges.append(byteRange)
        }
        return indexData
    }
}
