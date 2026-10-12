import CMAFKit
import XCTest
@testable import SiTVATV

final class DASHClearKeyMediaPipelineTests: XCTestCase {
    func testLoadsParsesAndDecryptsSelectedTrackSample() async throws {
        let key = try XCTUnwrap(Data(hexString: "2b7e151628aed2a6abf7158809cf4f3c"))
        let iv = try XCTUnwrap(Data(hexString: "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"))
        let ciphertext = try XCTUnwrap(Data(hexString: "874d6191b620e3261bef6864990db6ce"))
        let plaintext = try XCTUnwrap(Data(hexString: "6bc1bee22e409f96e93d7e117393172a"))
        let keyID = Data(repeating: 0x11, count: 16)
        let resolved = makeSegment()
        let prepared = makePreparedTrack(keyID: keyID, segment: resolved)
        let sample = CMAFParsedSample(
            trackID: 1,
            bytes: ciphertext,
            durationInTimescale: 3000,
            compositionTimeOffset: 120,
            flags: .syncSample,
            encryption: .init(initializationVector: iv),
            decodeTime: 9000
        )
        let reader = StubMediaReader(parsed: makeParsedSegment(samples: [sample]))
        let loader = StubDASHLoader(payload: Data([0x01, 0x02, 0x03]))
        let pipeline = DASHClearKeyTrackPipeline(
            preparedTrack: prepared,
            material: ClearKeyMaterial(keyID: keyID, key: key),
            headers: ["Referer": "https://example.com/"],
            loader: loader,
            reader: reader
        )

        let output = try await pipeline.loadAndDecrypt(resolved)
        let clear = try XCTUnwrap(output.samples.first)

        XCTAssertEqual(output.segment, resolved)
        XCTAssertEqual(clear.bytes, plaintext)
        XCTAssertEqual(clear.trackID, sample.trackID)
        XCTAssertEqual(clear.durationInTimescale, sample.durationInTimescale)
        XCTAssertEqual(clear.compositionTimeOffset, sample.compositionTimeOffset)
        XCTAssertEqual(clear.flags, sample.flags)
        XCTAssertEqual(clear.decodeTime, sample.decodeTime)
        XCTAssertNil(clear.encryption)
        XCTAssertEqual(await reader.lastBytes(), Data([0x01, 0x02, 0x03]))

        try await pipeline.finalize()
        XCTAssertTrue(await reader.wasFinalized())
    }

    func testRejectsMediaSegmentWithoutSelectedTrack() async throws {
        let keyID = Data(repeating: 0x22, count: 16)
        let resolved = makeSegment()
        let prepared = makePreparedTrack(keyID: keyID, segment: resolved)
        let foreignSample = CMAFParsedSample(
            trackID: 99,
            bytes: Data([1, 2, 3]),
            durationInTimescale: 1000,
            compositionTimeOffset: 0,
            flags: .syncSample,
            encryption: .init(initializationVector: Data(repeating: 0, count: 16)),
            decodeTime: 0
        )
        let pipeline = DASHClearKeyTrackPipeline(
            preparedTrack: prepared,
            material: ClearKeyMaterial(keyID: keyID, key: Data(repeating: 0x33, count: 16)),
            loader: StubDASHLoader(payload: Data([0xAA])),
            reader: StubMediaReader(parsed: makeParsedSegment(samples: [foreignSample]))
        )

        do {
            _ = try await pipeline.loadAndDecrypt(resolved)
            XCTFail("Expected noSamplesForTrack")
        } catch {
            XCTAssertEqual(error as? DASHClearKeyMediaPipelineError, .noSamplesForTrack(1))
        }
    }

    private func makeSegment() -> DASHResolvedSegment {
        DASHResolvedSegment(
            number: 1,
            time: 0,
            duration: 1000,
            url: URL(string: "https://example.com/video/1.m4s")!
        )
    }

    private func makePreparedTrack(keyID: Data, segment: DASHResolvedSegment) -> DASHPreparedTrack {
        let representation = DASHRepresentation(
            id: "video-main",
            bandwidth: 2_000_000,
            width: 1920,
            height: 1080,
            mimeType: "video/mp4",
            codecs: "avc1.640028",
            baseURL: URL(string: "https://example.com/video/")!,
            segmentTemplate: nil,
            contentProtections: []
        )
        let plan = DASHTrackPlan(
            representation: representation,
            initializationURL: URL(string: "https://example.com/video/init.mp4")!,
            mediaSegments: [segment]
        )
        let encryption = CENCTrackInfo(
            trackID: 1,
            kind: .video,
            scheme: .cenc,
            keyID: keyID,
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

    private func makeParsedSegment(samples: [CMAFParsedSample]) -> ParsedMediaSegment {
        ParsedMediaSegment(
            segmentIndex: 0,
            samples: samples,
            movieFragmentSequenceNumbers: [1],
            baseMediaDecodeTimes: [1: 0],
            hasSegmentIndex: false,
            hasProducerReferenceTime: false,
            eventMessages: [],
            segmentIndices: [],
            isChunkedSegment: false,
            firstSampleIsSyncSample: true
        )
    }
}

private struct StubDASHLoader: DASHResourceLoading {
    let payload: Data

    func loadManifest(from url: URL, headers: [String: String]) async throws -> DASHManifest {
        throw StubPipelineError.unused
    }

    func loadData(from url: URL, headers: [String: String]) async throws -> Data {
        payload
    }
}

private actor StubMediaReader: CMAFMediaSegmentReading {
    private let parsed: ParsedMediaSegment
    private var receivedBytes: Data?
    private var finalized = false

    init(parsed: ParsedMediaSegment) {
        self.parsed = parsed
    }

    func appendSegmentBytes(_ bytes: Data) async throws -> ParsedMediaSegment {
        receivedBytes = bytes
        return parsed
    }

    func finalize() async throws {
        finalized = true
    }

    func lastBytes() -> Data? {
        receivedBytes
    }

    func wasFinalized() -> Bool {
        finalized
    }
}

private enum StubPipelineError: Error {
    case unused
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
