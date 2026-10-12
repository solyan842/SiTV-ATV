import CMAFKit
import CoreMedia
import Foundation

protocol DASHInitTrackReading {
    func tracks(from initializationData: Data) async throws -> [CMAFTrackConfiguration]
}

struct CMAFDASHInitTrackReader: DASHInitTrackReading {
    func tracks(from initializationData: Data) async throws -> [CMAFTrackConfiguration] {
        let reader = try await CMAFInitSegmentReader(bytes: initializationData)
        return reader.tracks()
    }
}

enum DASHPlaybackContextError: Error, Equatable {
    case missingTrackConfiguration(UInt32)
}

struct DASHPlaybackTrackContext {
    let preparedTrack: DASHPreparedTrack
    let configuration: CMAFTrackConfiguration
    let formatDescription: CMFormatDescription
}

struct DASHClearKeyPlaybackContext {
    let preparation: DASHClearKeyPreparation
    let video: DASHPlaybackTrackContext?
    let audio: DASHPlaybackTrackContext?
}

struct DASHPlaybackContextBuilder {
    private let trackReader: any DASHInitTrackReading
    private let videoFormatFactory: DASHVideoFormatFactory
    private let audioFormatFactory: DASHAudioFormatFactory

    init(
        trackReader: any DASHInitTrackReading = CMAFDASHInitTrackReader(),
        videoFormatFactory: DASHVideoFormatFactory = DASHVideoFormatFactory(),
        audioFormatFactory: DASHAudioFormatFactory = DASHAudioFormatFactory()
    ) {
        self.trackReader = trackReader
        self.videoFormatFactory = videoFormatFactory
        self.audioFormatFactory = audioFormatFactory
    }

    func make(
        preparation: DASHClearKeyPreparation
    ) async throws -> DASHClearKeyPlaybackContext {
        let video = try await preparation.video.map { preparedTrack in
            let configuration = try await configuration(for: preparedTrack)
            let format = try videoFormatFactory.makeFormatDescription(for: configuration)
            return DASHPlaybackTrackContext(
                preparedTrack: preparedTrack,
                configuration: configuration,
                formatDescription: format
            )
        }

        let audio = try await preparation.audio.map { preparedTrack in
            let configuration = try await configuration(for: preparedTrack)
            let format = try audioFormatFactory.makeFormatDescription(for: configuration)
            return DASHPlaybackTrackContext(
                preparedTrack: preparedTrack,
                configuration: configuration,
                formatDescription: format
            )
        }

        return DASHClearKeyPlaybackContext(
            preparation: preparation,
            video: video,
            audio: audio
        )
    }

    private func configuration(
        for preparedTrack: DASHPreparedTrack
    ) async throws -> CMAFTrackConfiguration {
        let tracks = try await trackReader.tracks(from: preparedTrack.initializationData)
        let trackID = preparedTrack.encryption.trackID
        guard let configuration = tracks.first(where: { $0.trackID == trackID }) else {
            throw DASHPlaybackContextError.missingTrackConfiguration(trackID)
        }
        return configuration
    }
}
