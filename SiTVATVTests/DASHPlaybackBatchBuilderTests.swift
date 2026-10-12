import CMAFKit
import CoreMedia
import XCTest
@testable import SiTVATV

final class DASHPlaybackBatchBuilderTests: XCTestCase {
    func testUsesEarliestPresentationTimeAcrossBuiltSamples() throws {
        let context = try makeAudioPlaybackContext()
        let later = makeSample(decodeTime: 4_800)
        let earlier = makeSample(decodeTime: 2_400)
        let output = DASHClearKeyMediaOutput(
            video: [],
            audio: [makeSegment(index: 1, samples: [later, earlier])]
        )

        let batch = try DASHPlaybackBatchBuilder().make(
            output: output,
            context: context
        )

        XCTAssertTrue(batch.video.isEmpty)
        XCTAssertEqual(batch.audio.count, 2)
        XCTAssertEqual(batch.sourceTime.value, 2_400)
        XCTAssertEqual(batch.sourceTime.timescale, 48_000)
    }

    func testRejectsEmptyMediaOutput() throws {
        let context = try makeAudioPlaybackContext()
        let output = DASHClearKeyMediaOutput(video: [], audio: [])

        XCTAssertThrowsError(
            try DASHPlaybackBatchBuilder().make(output: output, context: context)
        ) { error in
            XCTAssertEqual(
                error as? DASHPlaybackBatchBuilderError,
                .noSamples
            )
        }
    }

    private func makeAudioPlaybackContext() throws -> DASHClearKeyPlaybackContext {
        let track = makeAACTrack()
        let preparedTrack = makePreparedAudioTrack()
        let format = try DASHAudioFormatFactory().makeFormatDescription(for: track)
        let baseURL = URL(string: "https://example.com/")!
        let preparation = DASHClearKeyPreparation(
            manifest: DASHManifest(
                type: .static,
                minimumUpdatePeriod: nil,
                baseURL: baseURL,
                periods: []
            ),
            keyMaterial: ClearKeyMaterial(
                keyID: Data(repeating: 0x11, count: 16),
                key: Data(repeating: 0x22, count: 16)
            ),
            video: nil,
            audio: preparedTrack
        )
        let audioContext = DASHPlaybackTrackContext(
            preparedTrack: preparedTrack,
            configuration: track,
            formatDescription: format
        )
        return DASHClearKeyPlaybackContext(
            preparation: preparation,
            video: nil,
            audio: audioContext
        )
    }

    private func makeAACTrack() -> CMAFTrackConfiguration {
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
            timescale: 48_000,
            language: "eng",
            audioFields: CMAFTrackConfiguration.AudioFields(
                codec: .mp4a,
                codecConfiguration: .mp4Audio(descriptor),
                channelCount: 2,
                sampleRate: 48_000
            )
        )
    }

    private func makePreparedAudioTrack() -> DASHPreparedTrack {
        let baseURL = URL(string: "https://example.com/")!
        let representation = DASHRepresentation(
            id: "audio",
            bandwidth: 128_000,
            width: nil,
            height: nil,
            mimeType: "audio/mp4",
            codecs: "mp4a.40.2",
            baseURL: baseURL,
            segmentTemplate: nil,
            contentProtections: []
        )
        return DASHPreparedTrack(
            plan: DASHTrackPlan(
                representation: representation,
                initializationURL: baseURL.appendingPathComponent("audio-init.mp4"),
                mediaSegments: []
            ),
            initializationData: Data([0x00]),
            encryption: CENCTrackInfo(
                trackID: 2,
                kind: .audio,
                scheme: .cenc,
                keyID: Data(repeating: 0x11, count: 16),
                perSampleIVSize: 16,
                constantIV: nil,
                cryptByteBlock: 0,
                skipByteBlock: 0
            )
        )
    }

    private func makeSample(decodeTime: UInt64) -> CMAFParsedSample {
        CMAFParsedSample(
            trackID: 2,
            bytes: Data([0x21, 0x10, 0x56, 0xE5]),
            durationInTimescale: 1_024,
            compositionTimeOffset: 0,
            flags: .syncSample,
            encryption: nil,
            decodeTime: decodeTime
        )
    }

    private func makeSegment(
        index: Int,
        samples: [CMAFParsedSample]
    ) -> ParsedMediaSegment {
        ParsedMediaSegment(
            segmentIndex: index,
            samples: samples,
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
