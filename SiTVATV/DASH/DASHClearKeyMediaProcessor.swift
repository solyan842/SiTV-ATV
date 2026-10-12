import CMAFKit
import Foundation

protocol CMAFMediaSegmentParsing: Sendable {
    func appendSegmentBytes(_ bytes: Data) async throws -> ParsedMediaSegment
    func finalize() async throws
}

struct CMAFMediaSegmentParser: CMAFMediaSegmentParsing, Sendable {
    private let reader: CMAFMediaSegmentReader

    init(initSegmentData: Data) async throws {
        let initReader = try await CMAFInitSegmentReader(bytes: initSegmentData)
        let tracks = initReader.tracks()
        var encryptionContexts: [UInt32: TrackEncryptionBox] = [:]
        for track in tracks {
            if let parameters = track.encryptionParameters {
                encryptionContexts[track.trackID] = parameters.makeTrackEncryptionBox()
            }
        }

        reader = try CMAFMediaSegmentReader(
            initSegmentConfiguration: tracks,
            movieTimescale: initReader.movieTimescale(),
            trackEncryptionContexts: encryptionContexts
        )
    }

    func appendSegmentBytes(_ bytes: Data) async throws -> ParsedMediaSegment {
        try await reader.appendSegmentBytes(bytes)
    }

    func finalize() async throws {
        try await reader.finalize()
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
            guard sample.encryption != nil else {
                return sample
            }

            let clearBytes = try decryptor.decrypt(
                sample: sample,
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
