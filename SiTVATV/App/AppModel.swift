import AVFoundation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var activeSource: PlaylistSource = PlaylistSource(slot: 0, name: "", url: "")
    @Published var selectedGroup: String = "Tất cả"
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isPlayerPresented = false
    @Published private(set) var activeChannel: Channel?
    @Published private(set) var activeAttempt: PlaybackAttempt?

    let avPlayerEngine: AVPlayerEngine

    private let repository: PlaylistRepository
    private let coordinator: PlayerCoordinator

    init(repository: PlaylistRepository = PlaylistRepository()) {
        self.repository = repository
        let avPlayerEngine = AVPlayerEngine()
        self.avPlayerEngine = avPlayerEngine
        self.coordinator = PlayerCoordinator(engines: [avPlayerEngine])
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
        activeSource = await repository.activeSource()
        guard activeSource.isConfigured else { return }
        await loadPlaylist()
    }

    func loadPlaylist() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await repository.load()
            activeSource = result.source
            channels = result.channels
            if !groups.contains(selectedGroup) {
                selectedGroup = "Tất cả"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func configurePrimarySource(name: String, url: String) async {
        var sources = await repository.sources()
        if sources.isEmpty {
            sources = (0..<PlaylistRepository.sourceCount).map {
                PlaylistSource(slot: $0, name: "", url: "")
            }
        }
        sources[0] = PlaylistSource(slot: 0, name: name, url: url)
        await repository.saveSources(sources)
        await repository.selectSource(slot: 0)
        activeSource = await repository.activeSource()
        await loadPlaylist()
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

    func stopPlayback() async {
        await coordinator.stop()
        isPlayerPresented = false
        activeChannel = nil
        activeAttempt = nil
    }
}
