import Foundation

enum DASHPlaybackPlannerError: Error, Equatable {
    case missingPeriod
    case noPlayableRepresentations
    case missingPreservedRepresentation(String)
}

struct DASHTrackPlan: Sendable, Equatable {
    let representation: DASHRepresentation
    let initializationURL: URL
    let mediaSegments: [DASHResolvedSegment]
}

struct DASHPlaybackPlan: Sendable, Equatable {
    let video: DASHTrackPlan?
    let audio: DASHTrackPlan?
    let periodIdentity: String?

    init(
        video: DASHTrackPlan?,
        audio: DASHTrackPlan?,
        periodIdentity: String? = nil
    ) {
        self.video = video
        self.audio = audio
        self.periodIdentity = periodIdentity
    }

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
        let selected = try selectedPeriod(in: manifest)
        return try makePlan(
            from: selected.period,
            periodIdentity: selected.identity,
            manifest: manifest,
            maxVideoHeight: maxVideoHeight,
            segmentCount: segmentCount
        )
    }

    func refreshPlan(
        from manifest: DASHManifest,
        preserving current: DASHPlaybackPlan,
        segmentCount: Int = 6
    ) throws -> DASHPlaybackPlan {
        let selected = try selectedPeriod(in: manifest)

        if let currentIdentity = current.periodIdentity,
           currentIdentity != selected.identity {
            return try makePlan(
                from: selected.period,
                periodIdentity: selected.identity,
                manifest: manifest,
                maxVideoHeight: current.video?.representation.height,
                segmentCount: segmentCount
            )
        }

        let selection = segmentSelection(for: manifest)
        let video = try refreshedTrackPlan(
            current.video,
            adaptations: selected.period.adaptationSets.filter { isVideo($0) },
            segmentCount: segmentCount,
            selection: selection
        )
        let audio = try refreshedTrackPlan(
            current.audio,
            adaptations: selected.period.adaptationSets.filter { isAudio($0) },
            segmentCount: segmentCount,
            selection: selection
        )

        let plan = DASHPlaybackPlan(
            video: video,
            audio: audio,
            periodIdentity: current.periodIdentity ?? selected.identity
        )
        guard !plan.isEmpty else {
            throw DASHPlaybackPlannerError.noPlayableRepresentations
        }
        return plan
    }

    private func makePlan(
        from period: DASHPeriod,
        periodIdentity: String,
        manifest: DASHManifest,
        maxVideoHeight: Int?,
        segmentCount: Int
    ) throws -> DASHPlaybackPlan {
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

        let selection = segmentSelection(for: manifest)
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

        let plan = DASHPlaybackPlan(
            video: video,
            audio: audio,
            periodIdentity: periodIdentity
        )
        guard !plan.isEmpty else {
            throw DASHPlaybackPlannerError.noPlayableRepresentations
        }
        return plan
    }

    private func selectedPeriod(
        in manifest: DASHManifest
    ) throws -> (period: DASHPeriod, identity: String) {
        guard !manifest.periods.isEmpty else {
            throw DASHPlaybackPlannerError.missingPeriod
        }

        let index: Int
        switch manifest.type {
        case .static:
            index = 0
        case .dynamic:
            index = manifest.periods.count - 1
        }
        let period = manifest.periods[index]
        let identity: String
        if let id = period.id, !id.isEmpty {
            identity = "id:\(id)"
        } else {
            identity = "index:\(index)|base:\(period.baseURL.absoluteString)"
        }
        return (period, identity)
    }

    private func refreshedTrackPlan(
        _ current: DASHTrackPlan?,
        adaptations: [DASHAdaptationSet],
        segmentCount: Int,
        selection: DASHSegmentSelection
    ) throws -> DASHTrackPlan? {
        guard let current else { return nil }
        let representationID = current.representation.id
        let candidates = adaptations.flatMap(\.representations)
        guard let representation = candidates.first(where: { $0.id == representationID }) else {
            throw DASHPlaybackPlannerError.missingPreservedRepresentation(representationID)
        }
        return try makeTrackPlan(
            representation: representation,
            segmentCount: segmentCount,
            selection: selection
        )
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

    private func segmentSelection(for manifest: DASHManifest) -> DASHSegmentSelection {
        manifest.type == .dynamic ? .latest : .earliest
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
