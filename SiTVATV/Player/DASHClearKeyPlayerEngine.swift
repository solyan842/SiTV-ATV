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
    private let generationLock = NSLock()
    private var startGeneration: UInt64 = 0

    private(set) var activeRequest: PlaybackRequest?
    private(set) var playbackContext: DASHClearKeyPlaybackContext?

    init(
        preparer: any DASHClearKeyPreparing = DASHClearKeySession(),
        contextBuilder: any DASHPlaybackContextBuilding = DASHPlaybackContextBuilder(),
        playbackController: any DASHPlaybackControlling = DASHClearKeyPlaybackController(),
        maxVideoHeight: Int? = nil,
        segmentCount: Int = 2
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

        let generation = advanceGeneration()
        activeRequest = nil
        playbackContext = nil
        await playbackController.stop()
        guard isCurrent(generation) else {
            throw PlayerEngineError.stopped
        }

        do {
            let context = try await prepareContext(for: request.source)
            guard isCurrent(generation) else {
                throw PlayerEngineError.stopped
            }
            activeRequest = request
            playbackContext = context
        } catch let error as PlayerEngineError {
            throw error
        } catch {
            if isCurrent(generation) {
                activeRequest = nil
                playbackContext = nil
            }
            throw PlayerEngineError.failedToStart(String(describing: error))
        }
    }

    func resumePlayback() async throws {
        guard let request = activeRequest,
              var context = playbackContext else {
            throw PlayerEngineError.failedToStart("DASH engine is not prepared")
        }
        let generation = currentGeneration()

        while true {
            guard isCurrent(generation) else {
                throw PlayerEngineError.stopped
            }
            do {
                try await playbackController.resume(
                    context: context,
                    headers: request.source.headers
                )
                guard isCurrent(generation) else {
                    throw PlayerEngineError.stopped
                }
                return
            } catch DASHPlaybackControllerError.reprepareRequired {
                guard isCurrent(generation), activeRequest == request else {
                    throw PlayerEngineError.stopped
                }

                do {
                    let refreshedContext = try await prepareContext(for: request.source)
                    guard isCurrent(generation), activeRequest == request else {
                        throw PlayerEngineError.stopped
                    }
                    playbackContext = refreshedContext
                    context = refreshedContext
                } catch let error as PlayerEngineError {
                    throw error
                } catch {
                    throw PlayerEngineError.failedToStart(String(describing: error))
                }
            } catch let error as PlayerEngineError {
                throw error
            } catch {
                throw PlayerEngineError.failedToStart(String(describing: error))
            }
        }
    }

    func stop() async {
        _ = advanceGeneration()
        activeRequest = nil
        playbackContext = nil
        await playbackController.stop()
    }

    private func prepareContext(
        for source: StreamSource
    ) async throws -> DASHClearKeyPlaybackContext {
        let preparation = try await preparer.prepare(
            source: source,
            maxVideoHeight: maxVideoHeight,
            segmentCount: segmentCount
        )
        return try await contextBuilder.make(preparation: preparation)
    }

    private func advanceGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        startGeneration &+= 1
        return startGeneration
    }

    private func currentGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        return startGeneration
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        currentGeneration() == generation
    }

    private func normalized(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }
}
