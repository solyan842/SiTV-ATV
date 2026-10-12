import Foundation

actor PlayerCoordinator {
    private let router: PlayerRouter
    private let engines: [PlayerEngineKind: any PlayerEngine]
    private var activeEngine: (any PlayerEngine)?

    init(router: PlayerRouter = PlayerRouter(), engines: [any PlayerEngine]) {
        self.router = router
        self.engines = Dictionary(uniqueKeysWithValues: engines.map { ($0.kind, $0) })
    }

    func play(_ channel: Channel) async throws -> PlaybackAttempt {
        await stop()

        let attempts = router.attempts(for: channel)
        guard !attempts.isEmpty else {
            throw PlayerEngineError.unsupported
        }

        var lastError: Error = PlayerEngineError.unsupported

        for attempt in attempts {
            guard let engine = engines[attempt.engine], engine.canPlay(attempt.source) else {
                continue
            }

            do {
                let request = PlaybackRequest(
                    channel: channel,
                    sourceIndex: attempt.sourceIndex,
                    source: attempt.source
                )
                try await engine.start(request)
                activeEngine = engine
                return attempt
            } catch {
                lastError = error
                await engine.stop()
            }
        }

        throw lastError
    }

    func stop() async {
        guard let activeEngine else { return }
        self.activeEngine = nil
        await activeEngine.stop()
    }
}
