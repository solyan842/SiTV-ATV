import CMAFKit
import XCTest
@testable import SiTVATV

final class DASHClearKeyMediaProcessorTests: XCTestCase {
    func testDecryptsParsedSampleAndPreservesTiming() async throws {
        let key = try XCTUnwrap(Data(hex: "2b7e151628aed2a6abf7158809cf4f3c"))
        let iv = try XCTUnwrap(Data(hex: "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"))
        let ciphertext = try XCTUnwrap(Data(hex: "874d6191b620e3261bef6864990db6ce"))
        let plaintext = try XCTUnwrap(Data(hex: "6bc1bee22e409f96e93d7e117393172a"))
        let keyID = Data(repeating: 0x11, count: 16)

        let sample = CMAFParsedSample(
            trackID: 7,
            bytes: ciphertext,
            durationInTimescale: 3_000,
            compositionTimeOffset: 120,
            flags: .syncSample,
            encryption: .init(initializationVector: iv),
            decodeTime: 9_000
        )
        let parser = StubMediaParser(segment: makeSegment(sample: sample))
        let processor = DASHClearKeyMediaProcessor(
            parser: parser,
            track: makeTrackInfo(trackID: 7, keyID: keyID),
            material: ClearKeyMaterial(keyID: keyID, key: key)
        )

        let result = try await processor.process(segmentData: Data([0x01]))
        let clearSample = try XCTUnwrap(result.samples.first)

        XCTAssertEqual(clearSample.bytes, plaintext)
        XCTAssertNil(clearSample.encryption)
        XCTAssertEqual(clearSample.trackID, 7)
        XCTAssertEqual(clearSample.durationInTimescale, 3_000)
        XCTAssertEqual(clearSample.compositionTimeOffset, 120)
        XCTAssertEqual(clearSample.decodeTime, 9_000)
        XCTAssertEqual(clearSample.flags, .syncSample)
        XCTAssertEqual(result.segmentIndex, 4)
        XCTAssertEqual(result.movieFragmentSequenceNumbers, [12])
        XCTAssertEqual(result.baseMediaDecodeTimes[7], 9_000)

        try await processor.finalize()
        let wasFinalized = await parser.wasFinalized()
        XCTAssertTrue(wasFinalized)
    }

    func testRejectsSampleFromUnexpectedTrack() async throws {
        let keyID = Data(repeating: 0x22, count: 16)
        let sample = CMAFParsedSample(
            trackID: 99,
            bytes: Data([0x01]),
            durationInTimescale: 1,
            compositionTimeOffset: 0,
            flags: .syncSample,
            encryption: nil,
            decodeTime: 0
        )
        let processor = DASHClearKeyMediaProcessor(
            parser: StubMediaParser(segment: makeSegment(sample: sample)),
            track: makeTrackInfo(trackID: 7, keyID: keyID),
            material: ClearKeyMaterial(
                keyID: keyID,
                key: Data(repeating: 0x33, count: 16)
            )
        )

        do {
            _ = try await processor.process(segmentData: Data())
            XCTFail("Expected unexpectedTrackID")
        } catch {
            XCTAssertEqual(
                error as? DASHClearKeyMediaProcessorError,
                .unexpectedTrackID(99)
            )
        }
    }

    private func makeTrackInfo(trackID: UInt32, keyID: Data) -> CENCTrackInfo {
        CENCTrackInfo(
            trackID: trackID,
            kind: .video,
            scheme: .cenc,
            keyID: keyID,
            perSampleIVSize: 16,
            constantIV: nil,
            cryptByteBlock: 0,
            skipByteBlock: 0
        )
    }

    private func makeSegment(sample: CMAFParsedSample) -> ParsedMediaSegment {
        ParsedMediaSegment(
            segmentIndex: 4,
            samples: [sample],
            movieFragmentSequenceNumbers: [12],
            baseMediaDecodeTimes: [sample.trackID: sample.decodeTime],
            hasSegmentIndex: true,
            hasProducerReferenceTime: false,
            eventMessages: [],
            segmentIndices: [],
            isChunkedSegment: false,
            firstSampleIsSyncSample: true
        )
    }
}

private actor StubMediaParser: CMAFMediaSegmentParsing {
    private let segment: ParsedMediaSegment
    private var finalized = false

    init(segment: ParsedMediaSegment) {
        self.segment = segment
    }

    func appendSegmentBytes(_ bytes: Data) async throws -> ParsedMediaSegment {
        segment
    }

    func finalize() async throws {
        finalized = true
    }

    func wasFinalized() -> Bool {
        finalized
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
