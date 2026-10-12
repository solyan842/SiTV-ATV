import Foundation

protocol CENCInspecting {
    func inspect(initSegment data: Data) async throws -> CENCInspection
}

extension CMAFCENCInspector: CENCInspecting {}

enum DASHClearKeySessionError: Error, Equatable {
    case invalidManifestURL
    case unsupportedDRM
    case noProtectedTrack
    case keyIDNotPresentInSelectedTracks
}

struct DASHPreparedTrack: Sendable, Equatable {
    let plan: DASHTrackPlan
    let initializationData: Data
    let encryption: CENCTrackInfo
}

struct DASHClearKeyPreparation: Sendable, Equatable {
    let manifest: DASHManifest
    let keyMaterial: ClearKeyMaterial
    let video: DASHPreparedTrack?
    let audio: DASHPreparedTrack?
    let manifestURL: URL?

    init(
        manifest: DASHManifest,
        keyMaterial: ClearKeyMaterial,
        video: DASHPreparedTrack?,
        audio: DASHPreparedTrack?,
        manifestURL: URL? = nil
    ) {
        self.manifest = manifest
        self.keyMaterial = keyMaterial
        self.video = video
        self.audio = audio
        self.manifestURL = manifestURL
    }
}

struct DASHClearKeySession {
    private let loader: any DASHResourceLoading
    private let keyProvider: any ClearKeyProviding
    private let inspector: any CENCInspecting
    private let planner: DASHPlaybackPlanner

    init(
        loader: any DASHResourceLoading = DASHResourceLoader(),
        keyProvider: any ClearKeyProviding = PlaylistClearKeyProvider(),
        inspector: any CENCInspecting = CMAFCENCInspector(),
        planner: DASHPlaybackPlanner = DASHPlaybackPlanner()
    ) {
        self.loader = loader
        self.keyProvider = keyProvider
        self.inspector = inspector
        self.planner = planner
    }

    func prepare(
        source: StreamSource,
        maxVideoHeight: Int? = nil,
        segmentCount: Int = 6
    ) async throws -> DASHClearKeyPreparation {
        guard let manifestURL = URL(string: source.url) else {
            throw DASHClearKeySessionError.invalidManifestURL
        }
        guard source.drmType?.lowercased() == "clearkey" else {
            throw DASHClearKeySessionError.unsupportedDRM
        }

        let material = try keyProvider.material(for: source)
        let manifest = try await loader.loadManifest(
            from: manifestURL,
            headers: source.headers
        )
        let playbackPlan = try planner.makePlan(
            from: manifest,
            maxVideoHeight: maxVideoHeight,
            segmentCount: segmentCount
        )

        let video = try await prepareTrack(
            playbackPlan.video,
            material: material,
            headers: source.headers
        )
        let audio = try await prepareTrack(
            playbackPlan.audio,
            material: material,
            headers: source.headers
        )

        guard video != nil || audio != nil else {
            throw DASHClearKeySessionError.noProtectedTrack
        }

        return DASHClearKeyPreparation(
            manifest: manifest,
            keyMaterial: material,
            video: video,
            audio: audio,
            manifestURL: manifestURL
        )
    }

    private func prepareTrack(
        _ plan: DASHTrackPlan?,
        material: ClearKeyMaterial,
        headers: [String: String]
    ) async throws -> DASHPreparedTrack? {
        guard let plan else { return nil }

        let initData = try await loader.loadData(
            from: plan.initializationURL,
            headers: headers
        )
        let inspection = try await inspector.inspect(initSegment: initData)
        guard !inspection.tracks.isEmpty else {
            throw DASHClearKeySessionError.noProtectedTrack
        }
        guard let track = inspection.tracks.first(where: { $0.keyID == material.keyID }) else {
            throw DASHClearKeySessionError.keyIDNotPresentInSelectedTracks
        }
        try CMAFCENCInspector().validate(material: material, for: track)

        return DASHPreparedTrack(
            plan: plan,
            initializationData: initData,
            encryption: track
        )
    }
}
