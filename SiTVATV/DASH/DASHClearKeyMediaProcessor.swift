import CMAFKit
import Foundation

protocol CMAFMediaSegmentParsing: Sendable {
    func appendSegmentBytes(_ bytes: Data) async throws -> ParsedMediaSegment
    func finalize() async throws
}

struct CMAFMediaSegmentParser: CMAFMediaSegmentParsing, Sendable {
    private let parser: DASHOffsetAwareMediaParser

    init(initSegmentData: Data) async throws {
        parser = try await DASHOffsetAwareMediaParser(initSegmentData: initSegmentData)
    }

    func appendSegmentBytes(_ bytes: Data) async throws -> ParsedMediaSegment {
        try await parser.appendSegmentBytes(bytes)
    }

    func finalize() async throws {
        await parser.finalize()
    }
}

enum DASHClearKeyMediaProcessorError: Error, Equatable {
    case unexpectedTrackID(UInt32)
}

struct DASHClearKeyMediaProcessor: Sendable {
    private let parser: any CMAFMediaSegmentParsing
    private let track: CENCTrackInfo
    private let material: ClearKeyMaterial
    private let decryptor: CENCSampleDecryptor

    init(
        preparedTrack: DASHPreparedTrack,
        material: ClearKeyMaterial,
        decryptor: CENCSampleDecryptor = CENCSampleDecryptor()
    ) async throws {
        parser = try await CMAFMediaSegmentParser(
            initSegmentData: preparedTrack.initializationData
        )
        track = preparedTrack.encryption
        self.material = material
        self.decryptor = decryptor
    }

    init(
        parser: any CMAFMediaSegmentParsing,
        track: CENCTrackInfo,
        material: ClearKeyMaterial,
        decryptor: CENCSampleDecryptor = CENCSampleDecryptor()
    ) {
        self.parser = parser
        self.track = track
        self.material = material
        self.decryptor = decryptor
    }

    func process(segmentData: Data) async throws -> ParsedMediaSegment {
        let parsed = try await parser.appendSegmentBytes(segmentData)
        let samples = try parsed.samples.map { sample -> CMAFParsedSample in
            guard sample.trackID == track.trackID else {
                throw DASHClearKeyMediaProcessorError.unexpectedTrackID(sample.trackID)
            }

            let encryption: CMAFSampleInput.EncryptionMetadata?
            if let sampleEncryption = sample.encryption {
                encryption = sampleEncryption
            } else if track.perSampleIVSize == 0, track.constantIV != nil {
                // ISO/IEC 23001-7 permits tenc to carry a constant IV instead of
                // a per-sample IV in senc. In that mode there may be no senc
                // entry at all. The decryptor resolves an empty IV against the
                // track constant IV, so ciphertext must not be passed through.
                encryption = CMAFSampleInput.EncryptionMetadata(
                    initializationVector: Data(),
                    subsamples: nil
                )
            } else {
                encryption = nil
            }

            guard let encryption else {
                return sample
            }

            let clearBytes = try decryptor.decrypt(
                bytes: sample.bytes,
                encryption: encryption,
                track: track,
                material: material
            )
            return CMAFParsedSample(
                trackID: sample.trackID,
                bytes: clearBytes,
                durationInTimescale: sample.durationInTimescale,
                compositionTimeOffset: sample.compositionTimeOffset,
                flags: sample.flags,
                encryption: nil,
                decodeTime: sample.decodeTime
            )
        }

        return ParsedMediaSegment(
            segmentIndex: parsed.segmentIndex,
            samples: samples,
            movieFragmentSequenceNumbers: parsed.movieFragmentSequenceNumbers,
            baseMediaDecodeTimes: parsed.baseMediaDecodeTimes,
            hasSegmentIndex: parsed.hasSegmentIndex,
            hasProducerReferenceTime: parsed.hasProducerReferenceTime,
            eventMessages: parsed.eventMessages,
            segmentIndices: parsed.segmentIndices,
            isChunkedSegment: parsed.isChunkedSegment,
            firstSampleIsSyncSample: parsed.firstSampleIsSyncSample
        )
    }

    func finalize() async throws {
        try await parser.finalize()
    }
}
