import AVFoundation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let allGroupTitle = "Tất cả"
    private static let favoritesGroupTitle = "Yêu thích"
    private static let lastChannelKey = "sitv.lastChannelID"
    private static let lastGroupKey = "sitv.lastGroup"

    @Published private(set) var channels: [Channel] = []
    @Published private(set) var sources: [PlaylistSource] = []
    @Published private(set) var activeSource: PlaylistSource = PlaylistSource(slot: 0, name: "", url: "")
    @Published private(set) var favoriteChannelIDs: Set<String> = []
    @Published var selectedGroup: String = allGroupTitle
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isPlayerPresented = false
    @Published private(set) var activeChannel: Channel?
    @Published private(set) var activeAttempt: PlaybackAttempt?

    let avPlayerEngine: AVPlayerEngine
    let vlcPlayerEngine: VLCPlayerEngine
    let dashRenderer: DASHSynchronizedRenderer
    let dashClearKeyEngine: DASHClearKeyPlayerEngine

    private let repository: PlaylistRepository
    private let favoritesStore: FavoritesStore
    private let coordinator: PlayerCoordinator
    private let defaults: UserDefaults

    init(
        repository: PlaylistRepository = PlaylistRepository(),
        favoritesStore: FavoritesStore = FavoritesStore(),
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.favoritesStore = favoritesStore
        self.defaults = defaults

        let avPlayerEngine = AVPlayerEngine()
        let vlcPlayerEngine = VLCPlayerEngine()
        let dashRenderer = DASHSynchronizedRenderer()
        let dashController = DASHClearKeyPlaybackController(
            fixedRenderer: dashRenderer
        )
        let dashClearKeyEngine = DASHClearKeyPlayerEngine(
            playbackController: dashController
        )

        self.avPlayerEngine = avPlayerEngine
        self.vlcPlayerEngine = vlcPlayerEngine
        self.dashRenderer = dashRenderer
        self.dashClearKeyEngine = dashClearKeyEngine
        self.coordinator = PlayerCoordinator(
            engines: [dashClearKeyEngine, avPlayerEngine, vlcPlayerEngine]
        )
    }

    var groups: [String] {
        let reserved = Set([Self.allGroupTitle, Self.favoritesGroupTitle])
        let values = Set(
            channels
                .map(\.group)
                .filter { !$0.isEmpty && !reserved.contains($0) }
        )
        return [Self.allGroupTitle, Self.favoritesGroupTitle]
            + values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var visibleChannels: [Channel] {
        if selectedGroup == Self.allGroupTitle {
            return channels
        }
        if selectedGroup == Self.favoritesGroupTitle {
            return channels.filter { favoriteChannelIDs.contains($0.id) }
        }
        return channels.filter { $0.group == selectedGroup }
    }

    var isFavoritesSelected: Bool {
        selectedGroup == Self.favoritesGroupTitle
    }

    var activeChannelNumber: Int? {
        guard let activeChannel,
              let index = channels.firstIndex(where: { $0.id == activeChannel.id }) else {
            return nil
        }
        return index + 1
    }

    func isFavorite(_ channel: Channel) -> Bool {
        favoriteChannelIDs.contains(channel.id)
    }

    func bootstrap() async {
        await refreshFavorites()
        await refreshSources()
        guard activeSource.isConfigured else { return }
        await loadPlaylist()
    }

    func refreshFavorites() async {
        favoriteChannelIDs = await favoritesStore.channelIDs()
    }

    func toggleFavorite(_ channel: Channel) async {
        favoriteChannelIDs = await favoritesStore.toggle(channelID: channel.id)
    }

    func refreshSources() async {
        sources = await repository.sources()
        activeSource = await repository.activeSource()
    }

    func selectGroup(_ group: String) {
        guard groups.contains(group) else { return }
        selectedGroup = group
        defaults.set(group, forKey: Self.lastGroupKey)
    }

    func loadPlaylist(autoPlay: Bool = true) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await repository.load()
            activeSource = result.source
            sources = await repository.sources()
            channels = result.channels

            let rememberedGroup = defaults.string(forKey: Self.lastGroupKey)
            if let rememberedGroup, groups.contains(rememberedGroup) {
                selectedGroup = rememberedGroup
            } else if !groups.contains(selectedGroup) {
                selectedGroup = Self.allGroupTitle
            }

            guard autoPlay, !channels.isEmpty else { return }

            let rememberedChannelID = activeChannel?.id ?? defaults.string(forKey: Self.lastChannelKey)
            let target = rememberedChannelID
                .flatMap { id in channels.first(where: { $0.id == id }) }
                ?? visibleChannels.first
                ?? channels.first

            if let target {
                await play(target)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSources(_ values: [PlaylistSource], activeSlot: Int) async {
        await repository.saveSources(values)
        await repository.selectSource(slot: activeSlot)
        await refreshSources()
        if activeSource.isConfigured {
            selectedGroup = Self.allGroupTitle
            defaults.set(Self.allGroupTitle, forKey: Self.lastGroupKey)
            await loadPlaylist()
        } else {
            channels = []
            await stopPlayback()
        }
    }

    func selectSource(slot: Int) async {
        await repository.selectSource(slot: slot)
        await refreshSources()
        selectedGroup = Self.allGroupTitle
        defaults.set(Self.allGroupTitle, forKey: Self.lastGroupKey)
        guard activeSource.isConfigured else {
            channels = []
            await stopPlayback()
            return
        }
        await loadPlaylist()
    }

    func clearSource(slot: Int) async {
        await repository.clearSource(slot: slot)
        await refreshSources()
        if activeSource.isConfigured {
            await loadPlaylist()
        } else {
            channels = []
            await stopPlayback()
        }
    }

    func play(_ channel: Channel) async {
        errorMessage = nil
        do {
            try await startPlayback(channel)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stepChannel(_ delta: Int) async {
        let surfChannels = visibleChannels.isEmpty ? channels : visibleChannels
        guard !surfChannels.isEmpty else { return }

        let direction = delta < 0 ? -1 : 1
        let currentIndex = activeChannel
            .flatMap { current in surfChannels.firstIndex(where: { $0.id == current.id }) }
            ?? (direction > 0 ? -1 : 0)

        var lastError: Error?
        for attemptOffset in 1...surfChannels.count {
            var index = currentIndex + (attemptOffset * direction)
            index %= surfChannels.count
            if index < 0 { index += surfChannels.count }
            let candidate = surfChannels[index]

            do {
                try await startPlayback(candidate)
                return
            } catch {
                lastError = error
            }
        }

        errorMessage = lastError?.localizedDescription ?? "Không tìm thấy kênh hoạt động"
    }

    func resumeDASHPlayback() async {
        guard activeAttempt?.engine == .dashClearKey else { return }

        do {
            try await dashClearKeyEngine.resumePlayback()
        } catch let error as PlayerEngineError where error == .stopped {
            return
        } catch {
            errorMessage = error.localizedDescription
            await stopPlayback()
        }
    }

    func stopPlayback() async {
        await coordinator.stop()
        isPlayerPresented = false
        activeChannel = nil
        activeAttempt = nil
    }

    private func startPlayback(_ channel: Channel) async throws {
        let attempt = try await coordinator.play(channel)
        activeChannel = channel
        activeAttempt = attempt
        isPlayerPresented = true
        defaults.set(channel.id, forKey: Self.lastChannelKey)
    }
}
