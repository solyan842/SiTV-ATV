import Foundation

enum DASHLivePlanRefresherError: Error, Equatable {
    case notDynamicManifest
}

struct DASHLiveRefreshBatch: Sendable, Equatable {
    let manifest: DASHManifest
    let plan: DASHPlaybackPlan
    let videoSegments: [DASHResolvedSegment]
    let audioSegments: [DASHResolvedSegment]
    let nextRefreshInterval: TimeInterval

    var isEmpty: Bool {
        videoSegments.isEmpty && audioSegments.isEmpty
    }
}

actor DASHLivePlanRefresher {
    private let loader: any DASHResourceLoading
    private let planner: DASHPlaybackPlanner
    private let manifestURL: URL
    private let headers: [String: String]
    private let segmentCount: Int
    private let defaultRefreshInterval: TimeInterval
    private let minimumRefreshInterval: TimeInterval

    private var currentPlan: DASHPlaybackPlan
    private var videoTracker: DASHLiveSegmentTracker
    private var audioTracker: DASHLiveSegmentTracker

    init(
        manifestURL: URL,
        headers: [String: String],
        initialPlan: DASHPlaybackPlan,
        segmentCount: Int = 6,
        defaultRefreshInterval: TimeInterval = 2,
        minimumRefreshInterval: TimeInterval = 0.5,
        loader: any DASHResourceLoading = DASHResourceLoader(),
        planner: DASHPlaybackPlanner = DASHPlaybackPlanner()
    ) {
        self.manifestURL = manifestURL
        self.headers = headers
        self.currentPlan = initialPlan
        self.segmentCount = max(segmentCount, 1)
        self.defaultRefreshInterval = max(defaultRefreshInterval, 0.1)
        self.minimumRefreshInterval = max(minimumRefreshInterval, 0.1)
        self.loader = loader
        self.planner = planner
        self.videoTracker = DASHLiveSegmentTracker(
            seed: initialPlan.video?.mediaSegments ?? []
        )
        self.audioTracker = DASHLiveSegmentTracker(
            seed: initialPlan.audio?.mediaSegments ?? []
        )
    }

    func refresh() async throws -> DASHLiveRefreshBatch {
        let manifest = try await loader.loadManifest(
            from: manifestURL,
            headers: headers
        )
        guard manifest.type == .dynamic else {
            throw DASHLivePlanRefresherError.notDynamicManifest
        }

        let refreshedPlan = try planner.refreshPlan(
            from: manifest,
            preserving: currentPlan,
            segmentCount: segmentCount
        )
        let videoSegments = videoTracker.unseenSegments(
            from: refreshedPlan.video?.mediaSegments ?? []
        )
        let audioSegments = audioTracker.unseenSegments(
            from: refreshedPlan.audio?.mediaSegments ?? []
        )
        currentPlan = refreshedPlan

        let requestedInterval = manifest.minimumUpdatePeriod
            ?? defaultRefreshInterval
        let interval = max(requestedInterval, minimumRefreshInterval)

        return DASHLiveRefreshBatch(
            manifest: manifest,
            plan: refreshedPlan,
            videoSegments: videoSegments,
            audioSegments: audioSegments,
            nextRefreshInterval: interval
        )
    }
}
