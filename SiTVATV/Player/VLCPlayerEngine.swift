import Foundation
import UIKit
import VLCKit

final class VLCPlayerEngine: PlayerEngine {
    let kind: PlayerEngineKind = .vlc
    let mediaPlayer = VLCMediaPlayer()
    let renderView: UIView

    private let startupTimeoutNanoseconds: UInt64

    init(startupTimeoutSeconds: Double = 12) {
        startupTimeoutNanoseconds = UInt64(max(startupTimeoutSeconds, 1) * 1_000_000_000)
        renderView = UIView(frame: .zero)
        renderView.backgroundColor = .black
        mediaPlayer.drawable = renderView
    }

    func canPlay(_ source: StreamSource) -> Bool {
        let drm = source.drmType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard drm.isEmpty else { return false }
        guard URL(string: source.url) != nil else { return false }

        return source.headers.keys.allSatisfy { key in
            let normalized = key.lowercased()
            return normalized == "referer" ||
                normalized == "referrer" ||
                normalized == "user-agent" ||
                normalized == "useragent"
        }
    }

    func start(_ request: PlaybackRequest) async throws {
        guard canPlay(request.source), let url = URL(string: request.source.url) else {
            throw PlayerEngineError.unsupported
        }

        await stop()

        let media = VLCMedia(url: url)
        applyHTTPOptions(from: request.source.headers, to: media)
        mediaPlayer.drawable = renderView
        mediaPlayer.media = media
        mediaPlayer.play()

        let startedAt = ContinuousClock.now
        let timeout = Duration.nanoseconds(Int64(min(startupTimeoutNanoseconds, UInt64(Int64.max))))

        while ContinuousClock.now - startedAt < timeout {
            if mediaPlayer.isPlaying {
                return
            }

            switch mediaPlayer.state {
            case .error:
                throw PlayerEngineError.failedToStart("VLCKit không thể mở stream")
            case .stopped:
                if ContinuousClock.now - startedAt > .seconds(1) {
                    throw PlayerEngineError.failedToStart("VLCKit đã dừng trước khi phát")
                }
            default:
                break
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        throw PlayerEngineError.failedToStart("VLCKit startup timed out")
    }

    func stop() async {
        mediaPlayer.stop()
        mediaPlayer.media = nil
    }

    private func applyHTTPOptions(from headers: [String: String], to media: VLCMedia) {
        for (key, value) in headers {
            switch key.lowercased() {
            case "referer", "referrer":
                media.addOption(":http-referrer=\(value)")
            case "user-agent", "useragent":
                media.addOption(":http-user-agent=\(value)")
            default:
                break
            }
        }
    }
}
