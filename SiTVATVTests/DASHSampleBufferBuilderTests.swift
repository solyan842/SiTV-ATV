import CMAFKit
import CoreMedia
import XCTest
@testable import SiTVATV

final class DASHSampleBufferBuilderTests: XCTestCase {
    func testBuildsAACSampleWithDecodePresentationAndDurationTiming() throws {
        let track = makeAACTrack()
        let format = try DASHAudioFormatFactory().makeFormatDescription(for: track)
        let payload = Data([0x21, 0x10, 0x56, 0xE5])
        let sample = CMAFParsedSample(
            trackID: 2,
            bytes: payload,
            durationInTimescale: 1_024,
            compositionTimeOffset: -512,
            flags: .syncSample,
            encryption: nil,
            decodeTime: 4_800
        )

        let buffer = try DASHSampleBufferBuilder().makeSampleBuffer(
            sample: sample,
            track: track,
            formatDescription: format
        )

        XCTAssertEqual(CMSampleBufferGetDecodeTimeStamp(buffer).value, 4_800)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(buffer).value, 4_288)
        XCTAssertEqual(CMSampleBufferGetDuration(buffer).value, 1_024)
        XCTAssertEqual(CMSampleBufferGetDecodeTimeStamp(buffer).timescale, 48_000)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(buffer).timescale, 48_000)
        XCTAssertEqual(CMSampleBufferGetDuration(buffer).timescale, 48_000)
        XCTAssertEqual(CMSampleBufferGetTotalSampleSize(buffer), payload.count)

        let dataBuffer = try XCTUnwrap(CMSampleBufferGetDataBuffer(buffer))
        var copied = Data(count: payload.count)
        let status = copied.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(
                dataBuffer,
                atOffset: 0,
                dataLength: payload.count,
                destination: bytes.baseAddress!
            )
        }
        XCTAssertEqual(status, noErr)
        XCTAssertEqual(copied, payload)
    }

    func testMarksNonSyncSampleAttachment() throws {
        let track = makeAACTrack()
        let format = try DASHAudioFormatFactory().makeFormatDescription(for: track)
        let sample = CMAFParsedSample(
            trackID: 2,
            bytes: Data([0x01, 0x02]),
            durationInTimescale: 1_024,
            compositionTimeOffset: 0,
            flags: .nonSyncSample,
            encryption: nil,
            decodeTime: 0
        )

        let buffer = try DASHSampleBufferBuilder().makeSampleBuffer(
            sample: sample,
            track: track,
            formatDescription: format
        )
        let attachments = try XCTUnwrap(
            CMSampleBufferGetSampleAttachmentsArray(
                buffer,
                createIfNecessary: false
            )
        )
        XCTAssertGreaterThan(CFArrayGetCount(attachments), 0)
        let dictionary = unsafeBitCast(
            CFArrayGetValueAtIndex(attachments, 0),
            to: CFDictionary.self
        )
        let value = CFDictionaryGetValue(
            dictionary,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()
        )
        XCTAssertEqual(
            value,
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
    }

    func testRejectsZeroTimescale() throws {
        let track = makeAACTrack(timescale: 0)
        let format = try DASHAudioFormatFactory().makeFormatDescription(for: track)
        let sample = CMAFParsedSample(
            trackID: 2,
            bytes: Data([0x01]),
            durationInTimescale: 1,
            compositionTimeOffset: 0,
            flags: .syncSample,
            encryption: nil,
            decodeTime: 0
        )

        XCTAssertThrowsError(
            try DASHSampleBufferBuilder().makeSampleBuffer(
                sample: sample,
                track: track,
                formatDescription: format
            )
        ) { error in
            XCTAssertEqual(
                error as? DASHSampleBufferBuilderError,
                .invalidTimescale(0)
            )
        }
    }

    private func makeAACTrack(
        timescale: UInt32 = 48_000
    ) -> CMAFTrackConfiguration {
        let descriptor = ElementaryStreamDescriptor(
            esID: 2,
            decoderConfig: .init(
                objectTypeIndication: .audioISO14496_3,
                streamType: .audioStream,
                upStream: false,
                bufferSizeDB: 0,
                maxBitrate: 128_000,
                avgBitrate: 128_000,
                decoderSpecificInfo: Data([0x11, 0x90])
            )
        )
        return CMAFTrackConfiguration(
            trackID: 2,
            kind: .audio,
            profile: .basic,
            timescale: timescale,
            language: "eng",
            audioFields: CMAFTrackConfiguration.AudioFields(
                codec: .mp4a,
                codecConfiguration: .mp4Audio(descriptor),
                channelCount: 2,
                sampleRate: 48_000
            )
        )
    }
}
