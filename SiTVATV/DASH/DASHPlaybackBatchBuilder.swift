import CoreMedia
import Foundation

enum DASHPlaybackBatchBuilderError: Error, Equatable {
    case missingVideoContext
    case missingAudioContext
    case noSamples
}

struct DASHPlaybackBatch {
    let video: [CMSampleBuffer]
    let audio: [CMSampleBuffer]
    let sourceTime: CMTime

    var isEmpty: Bool {
        video.isEmpty && audio.isEmpty
    }
}

struct DASHPlaybackBatchBuilder {
    private let sampleBufferBuilder: DASHSampleBufferBuilder

    init(sampleBufferBuilder: DASHSampleBufferBuilder = DASHSampleBufferBuilder()) {
        self.sampleBufferBuilder = sampleBufferBuilder
    }

    func make(
        output: DASHClearKeyMediaOutput,
        context: DASHClearKeyPlaybackContext
    ) throws -> DASHPlaybackBatch {
        let video = try makeBuffers(
            segments: output.video,
            context: context.video,
            missingContextError: .missingVideoContext
        )
        let audio = try makeBuffers(
            segments: output.audio,
            context: context.audio,
            missingContextError: .missingAudioContext
        )

        let allBuffers = video + audio
        guard let sourceTime = earliestPresentationTime(in: allBuffers) else {
            throw DASHPlaybackBatchBuilderError.noSamples
        }

        return DASHPlaybackBatch(
            video: video,
            audio: audio,
            sourceTime: sourceTime
        )
    }

    private func makeBuffers(
        segments: [ParsedMediaSegment],
        context: DASHPlaybackTrackContext?,
        missingContextError: DASHPlaybackBatchBuilderError
    ) throws -> [CMSampleBuffer] {
        let samples = segments.flatMap(\.samples)
        guard !samples.isEmpty else { return [] }
        guard let context else {
            throw missingContextError
        }

        return try samples.map { sample in
            try sampleBufferBuilder.makeSampleBuffer(
                sample: sample,
                track: context.configuration,
                formatDescription: context.formatDescription
            )
        }
    }

    private func earliestPresentationTime(
        in buffers: [CMSampleBuffer]
    ) -> CMTime? {
        var earliest: CMTime?
        for buffer in buffers {
            let time = CMSampleBufferGetPresentationTimeStamp(buffer)
            guard time.isValid else { continue }
            if let current = earliest {
                if CMTimeCompare(time, current) < 0 {
                    earliest = time
                }
            } else {
                earliest = time
            }
        }
        return earliest
    }
}
