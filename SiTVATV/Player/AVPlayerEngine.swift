import AVFoundation
import Foundation

final class AVPlayerEngine: PlayerEngine {
    let kind: PlayerEngineKind = .avPlayer
    let player = AVPlayer()

    private let startupTimeoutNanoseconds: UInt64

    init(startupTimeoutSeconds: Double = 12) {
        startupTimeoutNanoseconds = UInt64(max(startupTimeoutSeconds, 1) * 1_000_000_000)
        // Live TV channel changes should start rendering as soon as data is
        // available instead of waiting for AVPlayer's conservative stall buffer.
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
        item.preferredForwardBufferDuration = 1.0
        player.replaceCurrentItem(with: item)
        player.play()

        let startedAt = ContinuousClock.now
        let timeout = Duration.nanoseconds(Int64(min(startupTimeoutNanoseconds, UInt64(Int64.max))))

        while ContinuousClock.now - startedAt < timeout {
            switch item.status {
            case .readyToPlay:
                return
            case .failed:
                throw PlayerEngineError.failedToStart(item.error?.localizedDescription ?? "AVPlayer failed")
            case .unknown:
                try await Task.sleep(nanoseconds: 50_000_000)
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
