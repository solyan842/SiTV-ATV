import Foundation

protocol DASHClearKeyPreparing {
    func prepare(
        source: StreamSource,
        maxVideoHeight: Int?,
        segmentCount: Int
    ) async throws -> DASHClearKeyPreparation
}

extension DASHClearKeySession: DASHClearKeyPreparing {}

protocol DASHPlaybackContextBuilding {
    func make(
        preparation: DASHClearKeyPreparation
    ) async throws -> DASHClearKeyPlaybackContext
}

extension DASHPlaybackContextBuilder: DASHPlaybackContextBuilding {}

final class DASHClearKeyPlayerEngine: PlayerEngine {
    let kind: PlayerEngineKind = .dashClearKey

    private let preparer: any DASHClearKeyPreparing
    private let contextBuilder: any DASHPlaybackContextBuilding
    private let playbackController: any DASHPlaybackControlling
    private let maxVideoHeight: Int?
    private let segmentCount: Int

    private(set) var activeRequest: PlaybackRequest?
    private(set) var playbackContext: DASHClearKeyPlaybackContext?

    init(
        preparer: any DASHClearKeyPreparing = DASHClearKeySession(),
        contextBuilder: any DASHPlaybackContextBuilding = DASHPlaybackContextBuilder(),
        playbackController: any DASHPlaybackControlling = DASHClearKeyPlaybackController(),
        maxVideoHeight: Int? = nil,
        segmentCount: Int = 6
    ) {
        self.preparer = preparer
        self.contextBuilder = contextBuilder
        self.playbackController = playbackController
        self.maxVideoHeight = maxVideoHeight
        self.segmentCount = max(segmentCount, 1)
    }

    var isPrepared: Bool {
        playbackContext != nil
    }

    func canPlay(_ source: StreamSource) -> Bool {
        guard URL(string: source.url) != nil else { return false }

        let manifest = normalized(source.manifestType)
        let drm = normalized(source.drmType)
        let url = source.url.lowercased()

        let isDASH = manifest == "mpd"
            || manifest == "dash"
            || url.contains(".mpd")
        let isClearKey = drm.contains("clearkey")
            || drm.contains("clear_key")
            || drm.contains("org.w3.clearkey")

        return isDASH && isClearKey
    }

    func start(_ request: PlaybackRequest) async throws {
        guard canPlay(request.source) else {
            throw PlayerEngineError.unsupported
        }

        await stop()

        do {
            let preparation = try await preparer.prepare(
                source: request.source,
                maxVideoHeight: maxVideoHeight,
                segmentCount: segmentCount
            )
            let context = try await contextBuilder.make(preparation: preparation)
            activeRequest = request
            playbackContext = context
        } catch let error as PlayerEngineError {
            throw error
        } catch {
            activeRequest = nil
            playbackContext = nil
            throw PlayerEngineError.failedToStart(String(describing: error))
        }
    }

    func resumePlayback() async throws {
        guard let request = activeRequest,
              let context = playbackContext else {
            throw PlayerEngineError.failedToStart("DASH engine is not prepared")
        }

        do {
            try await playbackController.resume(
                context: context,
                headers: request.source.headers
            )
        } catch let error as PlayerEngineError {
            throw error
        } catch {
            throw PlayerEngineError.failedToStart(String(describing: error))
        }
    }

    func stop() async {
        await playbackController.stop()
        activeRequest = nil
        playbackContext = nil
    }

    private func normalized(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }
}
