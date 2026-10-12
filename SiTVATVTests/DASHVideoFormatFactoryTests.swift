import CMAFKit
import XCTest
@testable import SiTVATV

final class DASHVideoFormatFactoryTests: XCTestCase {
    func testExtractsAVCParameterSetsInSPSPPSOrder() throws {
        let sps = Data([0x67, 0x42, 0xC0, 0x1E])
        let pps = Data([0x68, 0xCE, 0x3C, 0x80])
        let record = AVCDecoderConfigurationRecord(
            profileIndication: .baseline,
            profileCompatibility: AVCProfileCompatibility(rawValue: 0xE0),
            levelIndication: .level3,
            lengthSize: .fourBytes,
            sequenceParameterSets: [AVCParameterSet(rbspBytes: sps)],
            pictureParameterSets: [AVCParameterSet(rbspBytes: pps)]
        )
        let track = makeVideoTrack(codecConfiguration: .avc(record))

        let parameters = try DASHVideoCodecParameterExtractor().parameters(for: track)

        XCTAssertEqual(parameters.codec, .avc)
        XCTAssertEqual(parameters.parameterSets, [sps, pps])
        XCTAssertEqual(parameters.nalUnitHeaderLength, 4)
    }

    func testRejectsNonVideoTrack() throws {
        let track = CMAFTrackConfiguration(
            trackID: 2,
            kind: .audio,
            profile: .basic,
            timescale: 48_000,
            language: "eng",
            audioFields: CMAFTrackConfiguration.AudioFields(
                codec: .mp4a,
                codecConfiguration: .mp4Audio(
                    ElementaryStreamDescriptor(
                        esID: 2,
                        decoderConfig: .init(
                            objectTypeIndication: .aac,
                            streamType: .audio,
                            upStream: false,
                            bufferSizeDB: 0,
                            maxBitrate: 128_000,
                            avgBitrate: 128_000,
                            decoderSpecificInfo: Data([0x11, 0x90])
                        )
                    )
                ),
                channelCount: 2,
                sampleRate: 48_000
            )
        )

        XCTAssertThrowsError(
            try DASHVideoCodecParameterExtractor().parameters(for: track)
        ) { error in
            XCTAssertEqual(
                error as? DASHVideoFormatFactoryError,
                .notVideoTrack
            )
        }
    }

    private func makeVideoTrack(
        codecConfiguration: VideoCodecConfiguration
    ) -> CMAFTrackConfiguration {
        CMAFTrackConfiguration(
            trackID: 1,
            kind: .video,
            profile: .basic,
            timescale: 90_000,
            language: "und",
            videoFields: CMAFTrackConfiguration.VideoFields(
                width: 1920,
                height: 1080,
                codec: .avc1,
                codecConfiguration: codecConfiguration,
                frameRate: .init(numerator: 30, denominator: 1)
            )
        )
    }
}
