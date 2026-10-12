import CMAFKit
import Foundation

protocol CMAFMediaSegmentReading: Sendable {
    func appendSegmentBytes(_ bytes: Data) async throws -> ParsedMediaSegment
    func finalize() async throws
}

extension CMAFMediaSegmentReader: CMAFMediaSegmentReading {}

enum DASHClearKeyMediaPipelineError: Error, Equatable {
    case trackConfigurationMissing(UInt32)
    case noSamplesForTrack(UInt32)
}

struct DASHDecryptedMediaSegment: Sendable, Equatable {
    let segment: DASHResolvedSegment
    let samples: [CMAFParsedSample]
}

actor DASHClearKeyTrackPipeline {
    private let preparedTrack: DASHPreparedTrack
    private let material: ClearKeyMaterial
    private let headers: [String: String]
    private let loader: any DASHResourceLoading
    private let reader: any CMAFMediaSegmentReading
    private let decryptor: CENCSampleDecryptor

    static func make(
        preparedTrack: DASHPreparedTrack,
        material: ClearKeyMaterial,
        headers: [String: String] = [:],
        loader: any DASHResourceLoading = DASHResourceLoader()
    ) async throws -> DASHClearKeyTrackPipeline {
        let initReader = try await CMAFInitSegmentReader(bytes: preparedTrack.initializationData)
        let tracks = initReader.tracks()
        let trackID = preparedTrack.encryption.trackID
        guard tracks.contains(where: { $0.trackID == trackID }) else {
            throw DASHClearKeyMediaPipelineError.trackConfigurationMissing(trackID)
        }

        var encryptionContexts: [UInt32: TrackEncryptionBox] = [:]
        for track in tracks {
            if let parameters = track.encryptionParameters {
                encryptionContexts[track.trackID] = parameters.makeTrackEncryptionBox()
            }
        }

        let mediaReader = try CMAFMediaSegmentReader(
            initSegmentConfiguration: tracks,
            movieTimescale: initReader.movieTimescale(),
            trackEncryptionContexts: encryptionContexts
        )

        return DASHClearKeyTrackPipeline(
            preparedTrack: preparedTrack,
            material: material,
            headers: headers,
            loader: loader,
            reader: mediaReader
        )
    }

    init(
        preparedTrack: DASHPreparedTrack,
        material: ClearKeyMaterial,
        headers: [String: String] = [:],
        loader: any DASHResourceLoading,
        reader: any CMAFMediaSegmentReading,
        decryptor: CENCSampleDecryptor = CENCSampleDecryptor()
    ) {
        self.preparedTrack = preparedTrack
        self.material = material
        self.headers = headers
        self.loader = loader
        self.reader = reader
        self.decryptor = decryptor
    }

    func loadAndDecrypt(_ segment: DASHResolvedSegment) async throws -> DASHDecryptedMediaSegment {
        let bytes = try await loader.loadData(from: segment.url, headers: headers)
        let parsed = try await reader.appendSegmentBytes(bytes)
        let trackID = preparedTrack.encryption.trackID
        let trackSamples = parsed.samples.filter { $0.trackID == trackID }

        guard !trackSamples.isEmpty else {
            throw DASHClearKeyMediaPipelineError.noSamplesForTrack(trackID)
        }

        let clearSamples = try trackSamples.map { sample in
            let clearBytes = try decryptor.decrypt(
                sample: sample,
                track: preparedTrack.encryption,
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

        return DASHDecryptedMediaSegment(segment: segment, samples: clearSamples)
    }

    func finalize() async throws {
        try await reader.finalize()
    }
}
