import Foundation

struct PlaylistResult: Sendable {
    let source: PlaylistSource
    let channels: [Channel]
    let fromCache: Bool
}

enum PlaylistRepositoryError: LocalizedError {
    case noConfiguredSource
    case invalidURL
    case invalidEncoding
    case emptyPlaylist
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .noConfiguredSource: "Chưa cấu hình nguồn IPTV"
        case .invalidURL: "URL playlist không hợp lệ"
        case .invalidEncoding: "Playlist không phải UTF-8 hợp lệ"
        case .emptyPlaylist: "Playlist không có kênh hợp lệ"
        case let .httpStatus(code): "HTTP \(code)"
        }
    }
}

actor PlaylistRepository {
    static let sourceCount = 5
    static let defaultPlaylistURL = ""
    static let defaultPlaylistName = ""

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let parser: M3UParser
    private let decoder: any PlaylistDecoding
    private let session: URLSession
    private let cacheDirectory: URL

    private let activeSourceKey = "active_source"
    private let cachePrefix = "playlist-cache-"

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        parser: M3UParser = M3UParser(),
        decoder: any PlaylistDecoding = UTF8PlaylistDecoder(),
        session: URLSession? = nil,
        cacheDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.parser = parser
        self.decoder = decoder

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.httpAdditionalHeaders = [
            "User-Agent": "SiTV/0.1 tvOS",
            "Accept": "application/octet-stream, application/x-mpegURL, audio/mpegurl, text/plain, */*"
        ]
        self.session = session ?? URLSession(configuration: configuration)

        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.cacheDirectory = base.appendingPathComponent("SiTV/Playlists", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    func sources() -> [PlaylistSource] {
        (0..<Self.sourceCount).map { slot in
            let defaultName = slot == 0 ? Self.defaultPlaylistName : ""
            let defaultURL = slot == 0 ? Self.defaultPlaylistURL : ""
            return PlaylistSource(
                slot: slot,
                name: (defaults.string(forKey: nameKey(slot)) ?? defaultName)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                url: (defaults.string(forKey: urlKey(slot)) ?? defaultURL)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    func configuredSources() -> [PlaylistSource] {
        sources().filter(\.isConfigured)
    }

    func activeSourceIndex() -> Int {
        let configured = configuredSources()
        guard !configured.isEmpty else { return 0 }

        let stored = defaults.integer(forKey: activeSourceKey)
        if sources().indices.contains(stored), sources()[stored].isConfigured {
            return stored
        }
        return configured[0].slot
    }

    func activeSource() -> PlaylistSource {
        let all = sources()
        let index = activeSourceIndex()
        if all.indices.contains(index), all[index].isConfigured {
            return all[index]
        }
        return PlaylistSource(slot: 0, name: "", url: "")
    }

    func selectSource(slot: Int) {
        let all = sources()
        guard all.indices.contains(slot), all[slot].isConfigured else { return }
        defaults.set(slot, forKey: activeSourceKey)
    }

    func saveSources(_ values: [PlaylistSource]) {
        let previous = Dictionary(uniqueKeysWithValues: sources().map { ($0.slot, $0) })

        for slot in 0..<Self.sourceCount {
            let source = values.first(where: { $0.slot == slot })
            let name = source?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = source?.url.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let oldURL = previous[slot]?.url.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if oldURL != url {
                try? fileManager.removeItem(at: cacheFile(slot: slot))
            }

            defaults.set(name, forKey: nameKey(slot))
            defaults.set(url, forKey: urlKey(slot))
        }

        let active = activeSourceIndex()
        let all = sources()
        if !all.indices.contains(active) || !all[active].isConfigured {
            defaults.set(configuredSources().first?.slot ?? 0, forKey: activeSourceKey)
        }
    }

    func clearSource(slot: Int) {
        guard (0..<Self.sourceCount).contains(slot) else { return }

        defaults.set("", forKey: nameKey(slot))
        defaults.set("", forKey: urlKey(slot))
        try? fileManager.removeItem(at: cacheFile(slot: slot))

        if defaults.integer(forKey: activeSourceKey) == slot {
            defaults.set(configuredSources().first?.slot ?? 0, forKey: activeSourceKey)
        }
    }

    func resetSources() {
        for slot in 0..<Self.sourceCount {
            defaults.removeObject(forKey: nameKey(slot))
            defaults.removeObject(forKey: urlKey(slot))
            try? fileManager.removeItem(at: cacheFile(slot: slot))
        }
        defaults.set(0, forKey: activeSourceKey)
    }

    func playlistURL() -> String { activeSource().url }
    func playlistName() -> String { activeSource().name }

    func load() async throws -> PlaylistResult {
        let source = activeSource()
        guard source.isConfigured else { throw PlaylistRepositoryError.noConfiguredSource }

        try ensureCacheDirectory()
        let cache = cacheFile(slot: source.slot)
        if let cached = try? Data(contentsOf: cache),
           let text = try? decoder.decode(cached) {
            let channels = parser.parse(text)
            if !channels.isEmpty {
                Task { [source] in
                    try? await self.refreshCache(source: source, cache: cache)
                }
                return PlaylistResult(source: source, channels: channels, fromCache: true)
            }
        }

        let fresh = try await download(source.url)
        let text = try decoder.decode(fresh)
        let channels = parser.parse(text)
        guard !channels.isEmpty else { throw PlaylistRepositoryError.emptyPlaylist }

        try ensureCacheDirectory()
        try fresh.write(to: cache, options: .atomic)
        return PlaylistResult(source: source, channels: channels, fromCache: false)
    }

    private func refreshCache(source: PlaylistSource, cache: URL) async throws {
        let fresh = try await download(source.url)
        let text = try decoder.decode(fresh)
        guard !parser.parse(text).isEmpty else { throw PlaylistRepositoryError.emptyPlaylist }

        try ensureCacheDirectory()
        let current = try? Data(contentsOf: cache)
        if current != fresh {
            try fresh.write(to: cache, options: .atomic)
        }
    }

    private func download(_ urlValue: String) async throws -> Data {
        guard let url = URL(string: urlValue) else { throw PlaylistRepositoryError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw PlaylistRepositoryError.httpStatus(http.statusCode)
        }
        return data
    }

    private func ensureCacheDirectory() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: cacheDirectory.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return
            }
            try fileManager.removeItem(at: cacheDirectory)
        }
        try fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func nameKey(_ slot: Int) -> String { "source_name_\(slot)" }
    private func urlKey(_ slot: Int) -> String { "source_url_\(slot)" }
    private func cacheFile(slot: Int) -> URL {
        cacheDirectory.appendingPathComponent("\(cachePrefix)\(slot).m3u")
    }
}
