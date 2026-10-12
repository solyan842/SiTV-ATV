import AVFoundation
import Foundation

final class AVPlayerEngine: PlayerEngine {
    let kind: PlayerEngineKind = .avPlayer
    let player = AVPlayer()

    private let startupTimeoutNanoseconds: UInt64

    init(startupTimeoutSeconds: Double = 12) {
        startupTimeoutNanoseconds = UInt64(max(startupTimeoutSeconds, 1) * 1_000_000_000)
        player.automaticallyWaitsToMinimizeStalling = true
    }

    func canPlay(_ source: StreamSource) -> Bool {
        guard source.drmType?.isEmpty ?? true else {
            let drm = source.drmType?.lowercased() ?? ""
            guard drm.contains("fairplay") || drm.contains("com.apple.fps") || drm.contains("skd") else {
                return false
            }
            return source.headers.isEmpty
        }

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
                try await Task.sleep(nanoseconds: 100_000_000)
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
