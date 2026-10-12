import AVFoundation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var sources: [PlaylistSource] = []
    @Published private(set) var activeSource: PlaylistSource = PlaylistSource(slot: 0, name: "", url: "")
    @Published var selectedGroup: String = "Tất cả"
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
    private let coordinator: PlayerCoordinator

    init(repository: PlaylistRepository = PlaylistRepository()) {
        self.repository = repository

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
        let values = Set(channels.map(\.group).filter { !$0.isEmpty })
        return ["Tất cả"] + values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var visibleChannels: [Channel] {
        guard selectedGroup != "Tất cả" else { return channels }
        return channels.filter { $0.group == selectedGroup }
    }

    func bootstrap() async {
        await refreshSources()
        guard activeSource.isConfigured else { return }
        await loadPlaylist()
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
                selectedGroup = "Tất cả"
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
