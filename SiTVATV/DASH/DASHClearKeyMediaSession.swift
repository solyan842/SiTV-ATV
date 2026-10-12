import Foundation

protocol DASHClearKeyTrackProcessing: Sendable {
    func loadAndDecrypt(_ segment: DASHResolvedSegment) async throws -> DASHDecryptedMediaSegment
    func finalize() async throws
}

extension DASHClearKeyTrackPipeline: DASHClearKeyTrackProcessing {}

protocol DASHClearKeyTrackPipelineBuilding: Sendable {
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
        try await DASHClearKeyTrackPipeline.make(
            preparedTrack: preparedTrack,
            material: material,
            headers: headers
        )
    }
}

struct DASHClearKeyMediaOutput: Sendable, Equatable {
    let video: [DASHDecryptedMediaSegment]
    let audio: [DASHDecryptedMediaSegment]

    var isEmpty: Bool {
        video.isEmpty && audio.isEmpty
    }
}

actor DASHClearKeyMediaSession {
    private let videoTrack: DASHPreparedTrack?
    private let audioTrack: DASHPreparedTrack?
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
            videoTrack: preparation.video,
            audioTrack: preparation.audio,
            videoPipeline: videoPipeline,
            audioPipeline: audioPipeline
        )
    }

    init(
        videoTrack: DASHPreparedTrack?,
        audioTrack: DASHPreparedTrack?,
        videoPipeline: (any DASHClearKeyTrackProcessing)?,
        audioPipeline: (any DASHClearKeyTrackProcessing)?
    ) {
        self.videoTrack = videoTrack
        self.audioTrack = audioTrack
        self.videoPipeline = videoPipeline
        self.audioPipeline = audioPipeline
    }

    func consumePlannedSegments() async throws -> DASHClearKeyMediaOutput {
        let video = try await consume(
            track: videoTrack,
            pipeline: videoPipeline
        )
        let audio = try await consume(
            track: audioTrack,
            pipeline: audioPipeline
        )
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

    private func consume(
        track: DASHPreparedTrack?,
        pipeline: (any DASHClearKeyTrackProcessing)?
    ) async throws -> [DASHDecryptedMediaSegment] {
        guard let track, let pipeline else { return [] }

        var output: [DASHDecryptedMediaSegment] = []
        output.reserveCapacity(track.plan.mediaSegments.count)
        for segment in track.plan.mediaSegments {
            output.append(try await pipeline.loadAndDecrypt(segment))
        }
        return output
    }
}
