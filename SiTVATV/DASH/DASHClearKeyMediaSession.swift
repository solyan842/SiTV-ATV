import CMAFKit
import Foundation

protocol DASHClearKeyTrackProcessing {
    func processPlannedSegments() async throws -> [ParsedMediaSegment]
    func finalize() async throws
}

extension DASHClearKeyTrackPipeline: DASHClearKeyTrackProcessing {}

protocol DASHClearKeyTrackPipelineBuilding {
    func make(
        preparedTrack: DASHPreparedTrack,
        material: ClearKeyMaterial,
        headers: [String: String]
    ) async throws -> any DASHClearKeyTrackProcessing
}

struct DefaultDASHClearKeyTrackPipelineBuilder: DASHClearKeyTrackPipelineBuilding {
    func make(
        preparedTrack: DASHPreparedTrack,
        material: ClearKeyMaterial,
        headers: [String: String]
    ) async throws -> any DASHClearKeyTrackProcessing {
        try await DASHClearKeyTrackPipeline(
            preparedTrack: preparedTrack,
            material: material,
            headers: headers
        )
    }
}

struct DASHClearKeyMediaOutput {
    let video: [ParsedMediaSegment]
    let audio: [ParsedMediaSegment]

    var isEmpty: Bool {
        video.isEmpty && audio.isEmpty
    }
}

struct DASHClearKeyMediaSession {
    private let videoPipeline: (any DASHClearKeyTrackProcessing)?
    private let audioPipeline: (any DASHClearKeyTrackProcessing)?

    static func make(
        preparation: DASHClearKeyPreparation,
        headers: [String: String] = [:],
        builder: any DASHClearKeyTrackPipelineBuilding = DefaultDASHClearKeyTrackPipelineBuilder()
    ) async throws -> DASHClearKeyMediaSession {
        let videoPipeline: (any DASHClearKeyTrackProcessing)?
        if let video = preparation.video {
            videoPipeline = try await builder.make(
                preparedTrack: video,
                material: preparation.keyMaterial,
                headers: headers
            )
        } else {
            videoPipeline = nil
        }

        let audioPipeline: (any DASHClearKeyTrackProcessing)?
        if let audio = preparation.audio {
            audioPipeline = try await builder.make(
                preparedTrack: audio,
                material: preparation.keyMaterial,
                headers: headers
            )
        } else {
            audioPipeline = nil
        }

        return DASHClearKeyMediaSession(
            videoPipeline: videoPipeline,
            audioPipeline: audioPipeline
        )
    }

    init(
        videoPipeline: (any DASHClearKeyTrackProcessing)?,
        audioPipeline: (any DASHClearKeyTrackProcessing)?
    ) {
        self.videoPipeline = videoPipeline
        self.audioPipeline = audioPipeline
    }

    func processPlannedSegments() async throws -> DASHClearKeyMediaOutput {
        let video = try await videoPipeline?.processPlannedSegments() ?? []
        let audio = try await audioPipeline?.processPlannedSegments() ?? []
        return DASHClearKeyMediaOutput(video: video, audio: audio)
    }

    func finalize() async throws {
        var firstError: Error?

        if let videoPipeline {
            do {
                try await videoPipeline.finalize()
            } catch {
                firstError = error
            }
        }

        if let audioPipeline {
            do {
                try await audioPipeline.finalize()
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }
}
