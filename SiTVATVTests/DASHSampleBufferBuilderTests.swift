import CMAFKit
import CoreMedia
import XCTest
@testable import SiTVATV

final class DASHSampleBufferBuilderTests: XCTestCase {
    func testBuildsSampleBufferWithPayloadAndTiming() throws {
        let payload = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])
        let sample = CMAFParsedSample(
            trackID: 1,
            bytes: payload,
            durationInTimescale: 40,
            compositionTimeOffset: 5,
            flags: SampleFlags(),
            encryption: nil,
            decodeTime: 100
        )
        let track = makeTrack(timescale: 1_000)
        let format = try makeFormatDescription()

        let buffer = try DASHSampleBufferBuilder().makeSampleBuffer(
            sample: sample,
            track: track,
            formatDescription: format
        )

        XCTAssertEqual(CMSampleBufferGetDecodeTimeStamp(buffer), CMTime(value: 100, timescale: 1_000))
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(buffer), CMTime(value: 105, timescale: 1_000))
        XCTAssertEqual(CMSampleBufferGetDuration(buffer), CMTime(value: 40, timescale: 1_000))
        XCTAssertEqual(CMSampleBufferGetNumSamples(buffer), 1)

        let dataBuffer = try XCTUnwrap(CMSampleBufferGetDataBuffer(buffer))
        var copied = Data(count: payload.count)
        let status = copied.withUnsafeMutableBytes { destination in
            CMBlockBufferCopyDataBytes(
                dataBuffer,
                atOffset: 0,
                dataLength: payload.count,
                destination: destination.baseAddress!
            )
        }
        XCTAssertEqual(status, noErr)
        XCTAssertEqual(copied, payload)
    }

    func testRejectsZeroTimescaleBeforeBuildingBuffer() throws {
        let sample = CMAFParsedSample(
            trackID: 1,
            bytes: Data([0x01]),
            durationInTimescale: 1,
            compositionTimeOffset: 0,
            flags: SampleFlags(),
            encryption: nil,
            decodeTime: 0
        )

        XCTAssertThrowsError(
            try DASHSampleBufferBuilder().makeSampleBuffer(
                sample: sample,
                track: makeTrack(timescale: 0),
                formatDescription: makeFormatDescription()
            )
        ) { error in
            XCTAssertEqual(
                error as? DASHSampleBufferBuilderError,
                .invalidTimescale(0)
            )
        }
    }

    func testSupportsNegativeCompositionOffsetWhenPresentationTimeRemainsValid() throws {
        let sample = CMAFParsedSample(
            trackID: 1,
            bytes: Data([0x01, 0x02]),
            durationInTimescale: 20,
            compositionTimeOffset: -25,
            flags: SampleFlags(),
            encryption: nil,
            decodeTime: 100
        )
        let buffer = try DASHSampleBufferBuilder().makeSampleBuffer(
            sample: sample,
            track: makeTrack(timescale: 1_000),
            formatDescription: makeFormatDescription()
        )

        XCTAssertEqual(CMSampleBufferGetDecodeTimeStamp(buffer), CMTime(value: 100, timescale: 1_000))
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(buffer), CMTime(value: 75, timescale: 1_000))
    }

    private func makeTrack(timescale: UInt32) -> CMAFTrackConfiguration {
        CMAFTrackConfiguration(
            trackID: 1,
            kind: .video,
            profile: .basic,
            timescale: timescale,
            language: "und"
        )
    }

    private func makeFormatDescription() throws -> CMVideoFormatDescription {
        var description: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: 16,
            height: 16,
            extensions: nil,
            formatDescriptionOut: &description
        )
        XCTAssertEqual(status, noErr)
        return try XCTUnwrap(description)
    }
}
