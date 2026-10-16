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
    let keyMaterial: ClearKeyMaterial?

    init(
        plan: DASHTrackPlan,
        initializationData: Data,
        encryption: CENCTrackInfo,
        keyMaterial: ClearKeyMaterial? = nil
    ) {
        self.plan = plan
        self.initializationData = initializationData
        self.encryption = encryption
        self.keyMaterial = keyMaterial
    }
}

struct DASHClearKeyPreparation: Sendable, Equatable {
    let manifest: DASHManifest
    let keyMaterial: ClearKeyMaterial
    let video: DASHPreparedTrack?
    let audio: DASHPreparedTrack?
    let manifestURL: URL?
    let periodIdentity: String?

    init(
        manifest: DASHManifest,
        keyMaterial: ClearKeyMaterial,
        video: DASHPreparedTrack?,
        audio: DASHPreparedTrack?,
        manifestURL: URL? = nil,
        periodIdentity: String? = nil
    ) {
        self.manifest = manifest
        self.keyMaterial = keyMaterial
        self.video = video
        self.audio = audio
        self.manifestURL = manifestURL
        self.periodIdentity = periodIdentity
    }
}

private struct DASHClearKeyTrackCandidate {
    let plan: DASHTrackPlan
    let initializationData: Data
    let tracks: [CENCTrackInfo]
}

struct DASHClearKeySession {
    private let loader: any DASHResourceLoading
    private let keyProvider: any ClearKeyProviding
    private let licenseClient: any ClearKeyLicenseLoading
    private let inspector: any CENCInspecting
    private let planner: DASHPlaybackPlanner
    private let bmffValidator = DASHISOBMFFValidator()

    init(
        loader: any DASHResourceLoading = DASHResourceLoader(),
        keyProvider: any ClearKeyProviding = PlaylistClearKeyProvider(),
        licenseClient: any ClearKeyLicenseLoading = URLSessionClearKeyLicenseClient(),
        inspector: any CENCInspecting = CMAFCENCInspector(),
        planner: DASHPlaybackPlanner = DASHPlaybackPlanner()
    ) {
        self.loader = loader
        self.keyProvider = keyProvider
        self.licenseClient = licenseClient
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
        guard isClearKey(source.drmType) else {
            throw DASHClearKeySessionError.unsupportedDRM
        }

        let manifest = try await loader.loadManifest(
            from: manifestURL,
            headers: source.headers
        )
        let playbackPlan = try planner.makePlan(
            from: manifest,
            maxVideoHeight: maxVideoHeight,
            segmentCount: segmentCount
        )

        let videoCandidate = try await inspectTrack(
            playbackPlan.video,
            headers: source.headers
        )
        let audioCandidate = try await inspectTrack(
            playbackPlan.audio,
            headers: source.headers
        )

        let candidates = [videoCandidate, audioCandidate].compactMap { $0 }
        guard !candidates.isEmpty else {
            throw DASHClearKeySessionError.noProtectedTrack
        }

        let materials = try await resolveMaterials(
            for: source,
            candidates: candidates
        )

        let video = try makePreparedTrack(videoCandidate, materials: materials)
        let audio = try makePreparedTrack(audioCandidate, materials: materials)

        guard let representativeMaterial = video?.keyMaterial ?? audio?.keyMaterial else {
            throw DASHClearKeySessionError.keyIDNotPresentInSelectedTracks
        }

        return DASHClearKeyPreparation(
            manifest: manifest,
            keyMaterial: representativeMaterial,
            video: video,
            audio: audio,
            manifestURL: manifestURL,
            periodIdentity: playbackPlan.periodIdentity
        )
    }

    private func inspectTrack(
        _ plan: DASHTrackPlan?,
        headers: [String: String]
    ) async throws -> DASHClearKeyTrackCandidate? {
        guard let plan else { return nil }

        let initData = try await loader.loadData(
            from: plan.initializationURL,
            headers: headers
        )
        try bmffValidator.validateInitializationSegment(initData)

        let inspection = try await inspector.inspect(initSegment: initData)
        guard !inspection.tracks.isEmpty else {
            throw DASHClearKeySessionError.noProtectedTrack
        }

        return DASHClearKeyTrackCandidate(
            plan: plan,
            initializationData: initData,
            tracks: inspection.tracks
        )
    }

    private func resolveMaterials(
        for source: StreamSource,
        candidates: [DASHClearKeyTrackCandidate]
    ) async throws -> [Data: ClearKeyMaterial] {
        var seen = Set<Data>()
        let keyIDs = candidates
            .flatMap { $0.tracks.map(\.keyID) }
            .filter { seen.insert($0).inserted }

        guard !keyIDs.isEmpty else {
            throw DASHClearKeySessionError.noProtectedTrack
        }

        let resolved: [ClearKeyMaterial]
        if let licenseURL = clearKeyLicenseURL(for: source) {
            if let collectionClient = licenseClient as? any ClearKeyLicenseCollectionLoading {
                resolved = try await collectionClient.materials(
                    from: licenseURL,
                    keyIDs: keyIDs,
                    headers: source.licenseHeaders
                )
            } else {
                var values: [ClearKeyMaterial] = []
                for keyID in keyIDs {
                    values.append(
                        try await licenseClient.material(
                            from: licenseURL,
                            keyID: keyID,
                            headers: source.licenseHeaders
                        )
                    )
                }
                resolved = values
            }
        } else if let collectionProvider = keyProvider as? any ClearKeyCollectionProviding {
            resolved = try collectionProvider.materials(for: source)
        } else {
            resolved = [try keyProvider.material(for: source)]
        }

        let allowed = Set(keyIDs)
        let matching = resolved.filter { allowed.contains($0.keyID) }
        guard !matching.isEmpty else {
            throw DASHClearKeySessionError.keyIDNotPresentInSelectedTracks
        }

        return Dictionary(uniqueKeysWithValues: matching.map { ($0.keyID, $0) })
    }

    private func makePreparedTrack(
        _ candidate: DASHClearKeyTrackCandidate?,
        materials: [Data: ClearKeyMaterial]
    ) throws -> DASHPreparedTrack? {
        guard let candidate else { return nil }
        guard let track = candidate.tracks.first(where: { materials[$0.keyID] != nil }),
              let material = materials[track.keyID] else {
            throw DASHClearKeySessionError.keyIDNotPresentInSelectedTracks
        }
        try CMAFCENCInspector().validate(material: material, for: track)

        return DASHPreparedTrack(
            plan: candidate.plan,
            initializationData: candidate.initializationData,
            encryption: track,
            keyMaterial: material
        )
    }

    private func clearKeyLicenseURL(for source: StreamSource) -> URL? {
        if let value = source.licenseURI,
           let url = URL(string: value),
           isHTTP(url) {
            return url
        }
        if let value = source.drmKey,
           let url = URL(string: value),
           isHTTP(url) {
            return url
        }
        return nil
    }

    private func isHTTP(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func isClearKey(_ value: String?) -> Bool {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return normalized == "clearkey"
            || normalized == "clear_key"
            || normalized == "org.w3.clearkey"
            || normalized.contains("clearkey")
    }
}
