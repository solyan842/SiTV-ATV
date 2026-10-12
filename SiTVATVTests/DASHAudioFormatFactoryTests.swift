import CMAFKit
import XCTest
@testable import SiTVATV

final class DASHAudioFormatFactoryTests: XCTestCase {
    func testExtractsAACParametersAndMagicCookie() throws {
        let cookie = Data([0x11, 0x90])
        let track = makeAACTrack(cookie: cookie)

        let parameters = try DASHAudioCodecParameterExtractor().parameters(for: track)

        XCTAssertEqual(parameters.sampleRate, 48_000)
        XCTAssertEqual(parameters.channelCount, 2)
        XCTAssertEqual(parameters.magicCookie, cookie)
    }

    func testRejectsMissingDecoderSpecificInfo() throws {
        let track = makeAACTrack(cookie: nil)

        XCTAssertThrowsError(
            try DASHAudioCodecParameterExtractor().parameters(for: track)
        ) { error in
            XCTAssertEqual(
                error as? DASHAudioFormatFactoryError,
                .missingDecoderSpecificInfo
            )
        }
    }

    private func makeAACTrack(cookie: Data?) -> CMAFTrackConfiguration {
        let descriptor = ElementaryStreamDescriptor(
            esID: 2,
            decoderConfig: .init(
                objectTypeIndication: .audioISO14496_3,
                streamType: .audioStream,
                upStream: false,
                bufferSizeDB: 0,
                maxBitrate: 128_000,
                avgBitrate: 128_000,
                decoderSpecificInfo: cookie
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
}
