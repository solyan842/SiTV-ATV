import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    @State private var showSettings = false
    @State private var panel: NavigationPanel = .hidden
    @State private var panelHideTask: Task<Void, Never>?
    @State private var infoVisible = false
    @State private var infoHideTask: Task<Void, Never>?
    @FocusState private var focusTarget: FocusTarget?

    var body: some View {
        ZStack(alignment: .topLeading) {
            playbackBackground

            if model.channels.isEmpty, !model.isLoading {
                setupState
            }

            if infoVisible, let channel = model.activeChannel, panel == .hidden {
                nowPlaying(channel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(28)
                    .allowsHitTesting(false)
            }

            if panel != .hidden {
                navigationPanels
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(20)
            }

            if panel == .hidden, !model.channels.isEmpty {
                remoteCapture
                    .zIndex(30)
            }

            if model.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(28)
                    .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .zIndex(40)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .sheet(isPresented: $showSettings, onDismiss: restorePlayerFocus) {
            SourceSettingsView(model: model)
        }
        .alert("SiTV", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
                if !model.channels.isEmpty {
                    showChannelPanel()
                }
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear {
            restorePlayerFocus()
        }
        .onChange(of: model.activeChannel?.id) { _, _ in
            showNowInfo()
            if panel == .hidden {
                restorePlayerFocus()
            }
        }
        .onChange(of: model.channels.count) { _, count in
            if count > 0, model.activeChannel == nil {
                showChannelPanel()
            }
        }
        .onDisappear {
            panelHideTask?.cancel()
            infoHideTask?.cancel()
        }
    }

    @ViewBuilder
    private var playbackBackground: some View {
        if model.activeChannel != nil {
            PlayerView(model: model)
                .ignoresSafeArea()
        } else {
            Color.black
                .ignoresSafeArea()
        }
    }

    private var setupState: some View {
        VStack(spacing: 22) {
            Image(systemName: "tv")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)

            Text("SiTV")
                .font(.largeTitle.bold())

            Text(model.activeSource.isConfigured ? "Chưa có danh sách kênh" : "Chưa cấu hình nguồn IPTV")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button {
                showSettings = true
            } label: {
                Label("Nguồn IPTV", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var remoteCapture: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable()
            .focused($focusTarget, equals: .player)
            .onMoveCommand { direction in
                handlePlayerMove(direction)
            }
            .onPlayPauseCommand {
                showChannelPanel()
            }
    }

    private var navigationPanels: some View {
        HStack(spacing: 0) {
            if panel == .sources {
                sourcePanel
                    .frame(width: 300)
                    .transition(.move(edge: .leading))
            }

            if panel == .groups || panel == .sources {
                groupPanel
                    .frame(width: 320)
                    .transition(.move(edge: .leading))
            }

            channelPanel
                .frame(width: 520)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: panel)
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader("Nguồn IPTV", subtitle: "↑ ↓ chọn nguồn  •  OK tải  •  → quay lại")

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.sources.filter(\.isConfigured)) { source in
                        Button {
                            touchPanel()
                            Task {
                                await model.selectSource(slot: source.slot)
                                await MainActor.run {
                                    panel = .channels
                                    showNowInfo()
                                    focusCurrentChannel()
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: source.slot == model.activeSource.slot ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.name.isEmpty ? "Nguồn \(source.slot + 1)" : source.name)
                                        .lineLimit(1)
                                    Text(source.url)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .focused($focusTarget, equals: .source(source.slot))
                    }
                }
            }

            Text("@2026 SolYan-SiTV")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(Color.black.opacity(0.94))
        .onMoveCommand { direction in
            touchPanel()
            if direction == .right {
                showGroupPanel()
            }
        }
        .onExitCommand {
            showGroupPanel()
        }
    }

    private var groupPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader("Nhóm kênh", subtitle: "← nguồn IPTV  •  ↑ ↓ chọn  •  → quay lại")

            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(model.groups, id: \.self) { group in
                        Button {
                            touchPanel()
                            model.selectGroup(group)
                            panel = .channels
                            focusCurrentChannel()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: group == "Yêu thích" ? "star.fill" : "square.grid.2x2")
                                    .frame(width: 28)
                                Text(group)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(channelCount(for: group))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(
                                model.selectedGroup == group ? Color.white.opacity(0.13) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusTarget, equals: .group(group))
                    }
                }
            }
        }
        .padding(20)
        .background(Color.black.opacity(0.91))
        .onMoveCommand { direction in
            touchPanel()
            switch direction {
            case .left:
                showSourcePanel()
            case .right:
                showChannelPanel()
            default:
                break
            }
        }
        .onExitCommand {
            showChannelPanel()
        }
    }

    private var channelPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "tv.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("SiTV")
                        .font(.title2.bold())
                    Text(model.activeSource.name.isEmpty ? "Nguồn IPTV" : model.activeSource.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                Button {
                    touchPanel()
                    Task {
                        await model.loadPlaylist()
                        await MainActor.run {
                            showNowInfo()
                            focusCurrentChannel()
                        }
                    }
                } label: {
                    Label("Làm mới", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .focused($focusTarget, equals: .refresh)

                Button {
                    panelHideTask?.cancel()
                    showSettings = true
                } label: {
                    Label("Cài đặt", systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .focused($focusTarget, equals: .settings)
            }

            Text("Danh sách kênh  •  ← nhóm kênh  •  → đóng")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.visibleChannels.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Text(model.isFavoritesSelected ? "Chưa có kênh yêu thích" : "Nhóm này chưa có kênh")
                        .foregroundStyle(.secondary)
                    Button("Cài đặt nguồn") {
                        panelHideTask?.cancel()
                        showSettings = true
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.visibleChannels) { channel in
                                channelRow(channel)
                                    .id(channel.id)
                            }
                        }
                    }
                    .onChange(of: model.activeChannel?.id) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }

            HStack {
                Text("\(model.visibleChannels.count)/\(model.channels.count) kênh")
                Spacer()
                if let attempt = model.activeAttempt {
                    Text("\(attempt.engine.rawValue) · nguồn \(attempt.sourceIndex + 1)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color.black.opacity(0.87))
        .onMoveCommand { direction in
            touchPanel()
            switch direction {
            case .left:
                showGroupPanel()
            case .right:
                hidePanels()
            default:
                break
            }
        }
        .onPlayPauseCommand {
            panelHideTask?.cancel()
            showSettings = true
        }
        .onExitCommand {
            hidePanels()
        }
    }

    private func channelRow(_ channel: Channel) -> some View {
        Button {
            touchPanel()
            Task {
                await model.play(channel)
                await MainActor.run {
                    showNowInfo()
                    schedulePanelHide()
                }
            }
        } label: {
            HStack(spacing: 14) {
                Text(channelNumberText(channel))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 58, alignment: .leading)

                AsyncImage(url: channel.logoURL.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "tv")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 72, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(channel.group)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if model.isFavorite(channel) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                }

                if model.activeChannel?.id == channel.id {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(
                model.activeChannel?.id == channel.id ? Color.white.opacity(0.12) : Color.white.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .focused($focusTarget, equals: .channel(channel.id))
    }

    private func nowPlaying(_ channel: Channel) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(model.activeChannelNumber.map { String(format: "%02d", $0) } ?? "--")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
            Text(channel.name)
                .font(.title3.bold())
                .lineLimit(1)
            Text(channel.group)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
    }

    private func panelHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func handlePlayerMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            showChannelPanel()
        case .up:
            Task { await model.stepChannel(1) }
        case .down:
            Task { await model.stepChannel(-1) }
        case .right:
            guard let channel = model.activeChannel else { return }
            Task {
                await model.toggleFavorite(channel)
                await MainActor.run { showNowInfo() }
            }
        default:
            break
        }
    }

    private func showChannelPanel() {
        panel = .channels
        schedulePanelHide()
        focusCurrentChannel()
    }

    private func showGroupPanel() {
        panel = .groups
        schedulePanelHide()
        DispatchQueue.main.async {
            focusTarget = .group(model.selectedGroup)
        }
    }

    private func showSourcePanel() {
        let configured = model.sources.filter(\.isConfigured)
        guard !configured.isEmpty else {
            showSettings = true
            return
        }
        panel = .sources
        schedulePanelHide()
        let slot = configured.first(where: { $0.slot == model.activeSource.slot })?.slot ?? configured[0].slot
        DispatchQueue.main.async {
            focusTarget = .source(slot)
        }
    }

    private func hidePanels() {
        panelHideTask?.cancel()
        panel = .hidden
        restorePlayerFocus()
    }

    private func touchPanel() {
        schedulePanelHide()
    }

    private func schedulePanelHide() {
        panelHideTask?.cancel()
        panelHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !showSettings {
                    panel = .hidden
                    restorePlayerFocus()
                }
            }
        }
    }

    private func showNowInfo() {
        infoHideTask?.cancel()
        infoVisible = true
        infoHideTask = Task {
            try? await Task.sleep(for: .milliseconds(2_500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                infoVisible = false
            }
        }
    }

    private func focusCurrentChannel() {
        let target = model.activeChannel
            .flatMap { active in model.visibleChannels.first(where: { $0.id == active.id }) }
            ?? model.visibleChannels.first

        DispatchQueue.main.async {
            if let target {
                focusTarget = .channel(target.id)
            } else {
                focusTarget = .settings
            }
        }
    }

    private func restorePlayerFocus() {
        panelHideTask?.cancel()
        if panel == .hidden, !model.channels.isEmpty {
            DispatchQueue.main.async {
                focusTarget = .player
            }
        }
    }

    private func channelCount(for group: String) -> Int {
        switch group {
        case "Tất cả":
            return model.channels.count
        case "Yêu thích":
            return model.channels.filter { model.favoriteChannelIDs.contains($0.id) }.count
        default:
            return model.channels.filter { $0.group == group }.count
        }
    }

    private func channelNumberText(_ channel: Channel) -> String {
        guard let index = model.channels.firstIndex(where: { $0.id == channel.id }) else {
            return "--"
        }
        let number = index + 1
        return number < 100 ? String(format: "%02d", number) : String(number)
    }
}

private enum NavigationPanel: Equatable {
    case hidden
    case channels
    case groups
    case sources
}

private enum FocusTarget: Hashable {
    case player
    case channel(String)
    case group(String)
    case source(Int)
    case refresh
    case settings
}

#Preview {
    ContentView(model: AppModel())
}
