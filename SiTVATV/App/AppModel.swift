import AVFoundation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let allGroupTitle = "Tất cả"
    private static let favoritesGroupTitle = "Yêu thích"

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

    init(
        repository: PlaylistRepository = PlaylistRepository(),
        favoritesStore: FavoritesStore = FavoritesStore()
    ) {
        self.repository = repository
        self.favoritesStore = favoritesStore

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

    func loadPlaylist() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await repository.load()
            activeSource = result.source
            sources = await repository.sources()
            channels = result.channels
            if !groups.contains(selectedGroup) {
                selectedGroup = Self.allGroupTitle
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
            await loadPlaylist()
        } else {
            channels = []
        }
    }

    func selectSource(slot: Int) async {
        await repository.selectSource(slot: slot)
        await refreshSources()
        guard activeSource.isConfigured else {
            channels = []
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
        }
    }

    func play(_ channel: Channel) async {
        errorMessage = nil
        do {
            let attempt = try await coordinator.play(channel)
            activeChannel = channel
            activeAttempt = attempt
            isPlayerPresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
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
}
