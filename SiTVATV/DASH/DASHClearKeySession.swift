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

        let material = try await resolveMaterial(
            for: source,
            candidates: candidates
        )

        let video = try makePreparedTrack(videoCandidate, material: material)
        let audio = try makePreparedTrack(audioCandidate, material: material)

        guard video != nil || audio != nil else {
            throw DASHClearKeySessionError.noProtectedTrack
        }

        return DASHClearKeyPreparation(
            manifest: manifest,
            keyMaterial: material,
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

    private func resolveMaterial(
        for source: StreamSource,
        candidates: [DASHClearKeyTrackCandidate]
    ) async throws -> ClearKeyMaterial {
        let keyIDs = candidates.flatMap { candidate in
            candidate.tracks.map(\.keyID)
        }
        guard let firstKeyID = keyIDs.first else {
            throw DASHClearKeySessionError.noProtectedTrack
        }

        if let licenseURL = clearKeyLicenseURL(for: source) {
            let material = try await licenseClient.material(
                from: licenseURL,
                keyID: firstKeyID,
                headers: source.licenseHeaders
            )
            guard keyIDs.contains(material.keyID) else {
                throw DASHClearKeySessionError.keyIDNotPresentInSelectedTracks
            }
            return material
        }

        let material = try keyProvider.material(for: source)
        guard keyIDs.contains(material.keyID) else {
            throw DASHClearKeySessionError.keyIDNotPresentInSelectedTracks
        }
        return material
    }

    private func makePreparedTrack(
        _ candidate: DASHClearKeyTrackCandidate?,
        material: ClearKeyMaterial
    ) throws -> DASHPreparedTrack? {
        guard let candidate else { return nil }
        guard let track = candidate.tracks.first(where: { $0.keyID == material.keyID }) else {
            throw DASHClearKeySessionError.keyIDNotPresentInSelectedTracks
        }
        try CMAFCENCInspector().validate(material: material, for: track)

        return DASHPreparedTrack(
            plan: candidate.plan,
            initializationData: candidate.initializationData,
            encryption: track
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
