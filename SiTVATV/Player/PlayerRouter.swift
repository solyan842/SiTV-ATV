import Foundation

struct PlayerRouter: Sendable {
    func attempts(for channel: Channel) -> [PlaybackAttempt] {
        channel.sources.enumerated().flatMap { index, source in
            engines(for: source).map {
                PlaybackAttempt(sourceIndex: index, engine: $0, source: source)
            }
        }
    }

    func engines(for source: StreamSource) -> [PlayerEngineKind] {
        let manifest = normalized(source.manifestType)
        let drm = normalized(source.drmType)
        let url = source.url.lowercased()

        if isWidevine(drm) {
            return []
        }

        if isClearKey(drm) {
            return isDASH(manifest: manifest, url: url) ? [.dashClearKey] : []
        }

        if isFairPlay(drm) {
            return isHLS(manifest: manifest, url: url) ? [.avPlayer] : []
        }

        if isDASH(manifest: manifest, url: url) {
            return [.dash, .vlc]
        }

        if isHLS(manifest: manifest, url: url) {
            return [.avPlayer, .vlc]
        }

        return [.avPlayer, .vlc]
    }

    private func normalized(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func isHLS(manifest: String, url: String) -> Bool {
        manifest == "hls" || manifest == "m3u8" || url.contains(".m3u8")
    }

    private func isDASH(manifest: String, url: String) -> Bool {
        manifest == "mpd" || manifest == "dash" || url.contains(".mpd")
    }

    private func isClearKey(_ drm: String) -> Bool {
        drm.contains("clearkey") || drm.contains("clear_key") || drm.contains("org.w3.clearkey")
    }

    private func isWidevine(_ drm: String) -> Bool {
        drm.contains("widevine") || drm.contains("com.widevine.alpha")
    }

    private func isFairPlay(_ drm: String) -> Bool {
        drm.contains("fairplay") || drm.contains("com.apple.fps") || drm.contains("skd")
    }
}
