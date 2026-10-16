import AVFoundation
import Foundation

final class AVPlayerEngine: PlayerEngine {
    let kind: PlayerEngineKind = .avPlayer
    let player = AVPlayer()

    private let startupTimeoutNanoseconds: UInt64

    init(startupTimeoutSeconds: Double = 8) {
        startupTimeoutNanoseconds = UInt64(max(startupTimeoutSeconds, 1) * 1_000_000_000)
        // Live TV should start rendering as soon as playable data exists.
        // Do not let AVPlayer wait for its conservative anti-stall buffer.
        player.automaticallyWaitsToMinimizeStalling = false
    }

    func canPlay(_ source: StreamSource) -> Bool {
        let drm = source.drmType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard drm.isEmpty else { return false }

        let manifest = source.manifestType?.lowercased() ?? ""
        let url = source.url.lowercased()
        let isDASH = manifest == "mpd" || manifest == "dash" || url.contains(".mpd")
        return !isDASH && source.headers.isEmpty && URL(string: source.url) != nil
    }

    func start(_ request: PlaybackRequest) async throws {
        guard canPlay(request.source), let url = URL(string: request.source.url) else {
            throw PlayerEngineError.unsupported
        }

        let item = AVPlayerItem(url: url)
        // Android SiTV begins playback once roughly 1.2 s is available. On tvOS,
        // playImmediately() plus a small forward buffer gives the closest native
        // behavior without waiting several seconds for AVPlayer's default policy.
        item.preferredForwardBufferDuration = 0.5
        player.replaceCurrentItem(with: item)
        player.playImmediately(atRate: 1.0)

        let startedAt = ContinuousClock.now
        let timeout = Duration.nanoseconds(Int64(min(startupTimeoutNanoseconds, UInt64(Int64.max))))

        while ContinuousClock.now - startedAt < timeout {
            try Task.checkCancellation()
            switch item.status {
            case .readyToPlay:
                return
            case .failed:
                throw PlayerEngineError.failedToStart(item.error?.localizedDescription ?? "AVPlayer failed")
            case .unknown:
                try await Task.sleep(nanoseconds: 40_000_000)
            @unknown default:
                throw PlayerEngineError.failedToStart("Unknown AVPlayer item status")
            }
        }

        throw PlayerEngineError.failedToStart("AVPlayer startup timed out")
    }

    func stop() async {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
