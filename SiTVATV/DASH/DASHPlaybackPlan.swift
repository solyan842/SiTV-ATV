import Foundation

enum DASHPlaybackPlannerError: Error, Equatable {
    case missingPeriod
    case noPlayableRepresentations
}

struct DASHTrackPlan: Sendable, Equatable {
    let representation: DASHRepresentation
    let initializationURL: URL
    let mediaSegments: [DASHResolvedSegment]
}

struct DASHPlaybackPlan: Sendable, Equatable {
    let video: DASHTrackPlan?
    let audio: DASHTrackPlan?

    var isEmpty: Bool {
        video == nil && audio == nil
    }
}

struct DASHPlaybackPlanner {
    private let resolver = DASHSegmentResolver()

    func makePlan(
        from manifest: DASHManifest,
        maxVideoHeight: Int? = nil,
        segmentCount: Int = 6
    ) throws -> DASHPlaybackPlan {
        guard let period = manifest.periods.first else {
            throw DASHPlaybackPlannerError.missingPeriod
        }

        let videoCandidates = period.adaptationSets
            .filter { isVideo($0) }
            .flatMap(\.representations)
            .filter { representation in
                guard let maxVideoHeight else { return true }
                guard let height = representation.height else { return true }
                return height <= maxVideoHeight
            }

        let audioCandidates = period.adaptationSets
            .filter { isAudio($0) }
            .flatMap(\.representations)

        let selection: DASHSegmentSelection = manifest.type == .dynamic
            ? .latest
            : .earliest

        let video = try selectBest(videoCandidates).map {
            try makeTrackPlan(
                representation: $0,
                segmentCount: segmentCount,
                selection: selection
            )
        }
        let audio = try selectBest(audioCandidates).map {
            try makeTrackPlan(
                representation: $0,
                segmentCount: segmentCount,
                selection: selection
            )
        }

        let plan = DASHPlaybackPlan(video: video, audio: audio)
        guard !plan.isEmpty else {
            throw DASHPlaybackPlannerError.noPlayableRepresentations
        }
        return plan
    }

    private func makeTrackPlan(
        representation: DASHRepresentation,
        segmentCount: Int,
        selection: DASHSegmentSelection
    ) throws -> DASHTrackPlan {
        DASHTrackPlan(
            representation: representation,
            initializationURL: try resolver.initializationURL(for: representation),
            mediaSegments: try resolver.mediaSegments(
                for: representation,
                maxCount: segmentCount,
                selection: selection
            )
        )
    }

    private func selectBest(_ representations: [DASHRepresentation]) -> DASHRepresentation? {
        representations.max { lhs, rhs in
            let lhsBandwidth = lhs.bandwidth ?? 0
            let rhsBandwidth = rhs.bandwidth ?? 0
            if lhsBandwidth != rhsBandwidth {
                return lhsBandwidth < rhsBandwidth
            }
            let lhsPixels = (lhs.width ?? 0) * (lhs.height ?? 0)
            let rhsPixels = (rhs.width ?? 0) * (rhs.height ?? 0)
            return lhsPixels < rhsPixels
        }
    }

    private func isVideo(_ adaptation: DASHAdaptationSet) -> Bool {
        adaptation.contentType?.lowercased() == "video"
            || adaptation.mimeType?.lowercased().hasPrefix("video/") == true
            || adaptation.representations.contains {
                $0.mimeType?.lowercased().hasPrefix("video/") == true
            }
    }

    private func isAudio(_ adaptation: DASHAdaptationSet) -> Bool {
        adaptation.contentType?.lowercased() == "audio"
            || adaptation.mimeType?.lowercased().hasPrefix("audio/") == true
            || adaptation.representations.contains {
                $0.mimeType?.lowercased().hasPrefix("audio/") == true
            }
    }
}
