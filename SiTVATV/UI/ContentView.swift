import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    @State private var showSettings = false
    @State private var panel: NavigationPanel = .hidden
    @State private var panelHideTask: Task<Void, Never>?
    @State private var infoVisible = false
    @State private var infoHideTask: Task<Void, Never>?
    @State private var favoritePromptChannelID: String?
    @State private var favoriteNotice: FavoriteNotice?
    @FocusState private var focusTarget: FocusTarget?

    var body: some View {
        ZStack(alignment: .topLeading) {
            playbackBackground

            if model.channels.isEmpty, !model.isLoading {
                setupState
            }

            if infoVisible, let channel = model.activeChannel, panel == .hidden, favoritePromptChannelID == nil {
                nowPlaying(channel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(24)
                    .allowsHitTesting(false)

                brandOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(24)
                    .allowsHitTesting(false)
            }

            if panel != .hidden {
                navigationPanels
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(20)
            }

            if panel == .hidden, !model.channels.isEmpty, favoritePromptChannelID == nil {
                remoteCapture
                    .zIndex(30)
            }

            if favoritePromptChannelID != nil {
                favoritePromptOverlay
                    .zIndex(50)
            } else if let favoriteNotice {
                favoriteNoticeOverlay(favoriteNotice)
                    .zIndex(45)
            }

            if model.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(28)
                    .background(SiTVTheme.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .zIndex(40)
            }
        }
        .background(SiTVTheme.black)
        .ignoresSafeArea()
        .sheet(isPresented: $showSettings, onDismiss: {
            if model.channels.isEmpty {
                focusTarget = nil
            } else {
                showChannelPanel()
            }
        }) {
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
            if panel == .hidden, favoritePromptChannelID == nil {
                restorePlayerFocus()
            }
        }
        .onChange(of: model.channels.count) { _, count in
            if count > 0, model.activeChannel == nil {
                showChannelPanel()
            }
        }
        .onChange(of: focusTarget) { _, target in
            guard panel != .hidden else { return }
            switch target {
            case .settings, .refresh:
                panelHideTask?.cancel()
            default:
                schedulePanelHide()
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
            SiTVTheme.black.ignoresSafeArea()
        }
    }

    private var setupState: some View {
        VStack(spacing: 22) {
            SiTVLogoMark()
                .frame(width: 92, height: 92)

            Text("SiTV")
                .font(.largeTitle.bold())
                .foregroundStyle(SiTVTheme.text)

            Text(model.activeSource.isConfigured ? "Chưa có danh sách kênh" : "Chưa cấu hình nguồn IPTV")
                .font(.title3)
                .foregroundStyle(SiTVTheme.textDim)

            Button {
                panelHideTask?.cancel()
                showSettings = true
            } label: {
                Label("Nguồn IPTV", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
            .tint(SiTVTheme.orange)
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
                    .frame(width: 230)
                    .transition(.move(edge: .leading))
            }

            if panel == .groups || panel == .sources {
                groupPanel
                    .frame(width: 250)
                    .transition(.move(edge: .leading))
            }

            channelPanel
                .frame(width: 430)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeOut(duration: 0.16), value: panel)
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader("Nguồn IPTV", subtitle: "↑ ↓ chọn nguồn  •  OK tải  •  → quay lại")

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(configuredSources) { source in
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
                            HStack(spacing: 10) {
                                Image(systemName: source.slot == model.activeSource.slot ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(source.slot == model.activeSource.slot ? SiTVTheme.orange : SiTVTheme.textDim)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name.isEmpty ? "Nguồn \(source.slot + 1)" : source.name)
                                        .lineLimit(1)
                                        .foregroundStyle(SiTVTheme.text)
                                    Text(source.url)
                                        .font(.caption2)
                                        .foregroundStyle(SiTVTheme.textDim)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .background(sourceBackground(source))
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(focusTarget == .source(source.slot) ? 1.025 : 1)
                        .focused($focusTarget, equals: .source(source.slot))
                        .onMoveCommand { direction in
                            handleSourceMove(direction, slot: source.slot)
                        }
                    }
                }
                .padding(4)
            }

            Text("@2026 SolYan-SiTV")
                .font(.caption2)
                .foregroundStyle(SiTVTheme.textDim)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(SiTVTheme.sourcePanel)
        .onExitCommand {
            showGroupPanel()
        }
    }

    private var groupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader("Nhóm kênh", subtitle: "← nguồn IPTV  •  ↑ ↓ chọn  •  → quay lại")

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.groups, id: \.self) { group in
                        Button {
                            touchPanel()
                            model.selectGroup(group)
                            panel = .channels
                            focusCurrentChannel()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: group == "KÊNH YÊU THÍCH ♥" ? "heart.fill" : "square.grid.2x2")
                                    .frame(width: 24)
                                Text(group)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text("\(channelCount(for: group))")
                                    .font(.caption.monospacedDigit())
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .foregroundStyle(groupForeground(group))
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(groupBackground(group))
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(focusTarget == .group(group) ? 1.025 : 1)
                        .focused($focusTarget, equals: .group(group))
                        .onMoveCommand { direction in
                            handleGroupMove(direction, group: group)
                        }
                    }
                }
                .padding(4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(SiTVTheme.groupPanel)
        .onExitCommand {
            showChannelPanel()
        }
    }

    private var channelPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SiTVLogoMark()
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SiTV")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(SiTVTheme.text)
                    Text(model.activeSource.name.isEmpty ? "Nguồn IPTV" : model.activeSource.name)
                        .font(.caption2)
                        .foregroundStyle(SiTVTheme.textDim)
                        .lineLimit(1)
                }
            }
            .frame(height: 58)

            HStack(spacing: 12) {
                actionButton(title: "Làm mới", systemImage: "arrow.clockwise", target: .refresh) {
                    Task {
                        await model.loadPlaylist()
                        await MainActor.run {
                            showNowInfo()
                            focusCurrentChannel()
                        }
                    }
                }
                .onMoveCommand { direction in
                    handleTopActionMove(direction, target: .refresh)
                }

                actionButton(title: "Cài đặt", systemImage: "gearshape.fill", target: .settings) {
                    openSettings()
                }
                .onMoveCommand { direction in
                    handleTopActionMove(direction, target: .settings)
                }
            }
            .frame(height: 44)

            Text("Danh sách kênh  •  ← nhóm kênh")
                .font(.caption)
                .foregroundStyle(SiTVTheme.textDim)
                .padding(.leading, 8)

            if model.visibleChannels.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Text(model.isFavoritesSelected ? "Chưa có kênh yêu thích" : "Nhóm này chưa có kênh")
                        .foregroundStyle(SiTVTheme.textDim)
                    Button("Cài đặt nguồn") {
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SiTVTheme.orange)
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
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: model.activeChannel?.id) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text("\(model.visibleChannels.count)/\(model.channels.count) kênh")
                    .lineLimit(1)
                Spacer(minLength: 8)
                if model.isPlaybackStarting, let channel = model.activeChannel {
                    Text("Đang nạp · \(channel.name)")
                        .lineLimit(1)
                } else if let attempt = model.activeAttempt {
                    Text("\(attempt.engine.rawValue) · nguồn \(attempt.sourceIndex + 1)")
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(SiTVTheme.textDim)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 24,
                topTrailingRadius: 24
            )
            .fill(SiTVTheme.panel)
        )
        .overlay(alignment: .trailing) {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 24,
                topTrailingRadius: 24
            )
            .stroke(Color.white.opacity(0.20), lineWidth: 1)
        }
        .onPlayPauseCommand {
            openSettings()
        }
        .onExitCommand {
            hidePanels()
        }
    }

    private func channelRow(_ channel: Channel) -> some View {
        let target = FocusTarget.channel(channel.id)
        let focused = focusTarget == target
        let selected = model.activeChannel?.id == channel.id

        return Button {
            touchPanel()
            Task {
                await model.play(channel)
                await MainActor.run {
                    showNowInfo()
                    schedulePanelHide()
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(channelNumberText(channel))
                    .font(.system(size: 19, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SiTVTheme.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 48, alignment: .leading)

                AsyncImage(url: channel.logoURL.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "tv")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(SiTVTheme.textDim)
                        .padding(8)
                }
                .frame(width: 62, height: 46)
                .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(SiTVTheme.text)
                        .lineLimit(1)
                    Text(channel.group)
                        .font(.system(size: 12))
                        .foregroundStyle(SiTVTheme.textDim)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if model.isFavorite(channel) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if selected {
                    Image(systemName: "play.fill")
                        .foregroundStyle(SiTVTheme.orange)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(channelBackground(focused: focused, selected: selected))
        }
        .buttonStyle(.plain)
        .scaleEffect(focused ? 1.02 : 1)
        .focused($focusTarget, equals: target)
        .onMoveCommand { direction in
            handleChannelMove(direction, channel: channel)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        target: FocusTarget,
        action: @escaping () -> Void
    ) -> some View {
        let focused = focusTarget == target
        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SiTVTheme.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    focused ? SiTVTheme.orange : SiTVTheme.button,
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(focused ? 1.025 : 1)
        .focused($focusTarget, equals: target)
    }

    private var favoritePromptOverlay: some View {
        Button {
            commitFavoritePrompt()
        } label: {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusTarget, equals: .favoritePrompt)
        .overlay(alignment: .topTrailing) {
            favoriteBanner(heartColor: .white, text: "Lưu kênh yêu thích")
                .padding(24)
                .allowsHitTesting(false)
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                dismissFavoritePrompt()
            case .right:
                focusTarget = .favoritePrompt
            default:
                dismissFavoritePrompt()
            }
        }
        .onExitCommand {
            dismissFavoritePrompt()
        }
    }

    private func favoriteNoticeOverlay(_ notice: FavoriteNotice) -> some View {
        favoriteBanner(heartColor: notice.heartColor, text: notice.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(24)
            .allowsHitTesting(false)
    }

    private func favoriteBanner(heartColor: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(heartColor)
            Text(text)
                .font(.title3.bold())
                .foregroundStyle(SiTVTheme.text)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(SiTVTheme.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
    }

    private func nowPlaying(_ channel: Channel) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(model.activeChannelNumber.map { String(format: "%02d", $0) } ?? "--")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(SiTVTheme.orange)
                .lineLimit(1)
            Text(channel.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(SiTVTheme.text)
                .lineLimit(1)
            Text(channel.group)
                .font(.system(size: 13))
                .foregroundStyle(SiTVTheme.textDim)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(SiTVTheme.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 14))
    }

    private var brandOverlay: some View {
        HStack(spacing: 6) {
            SiTVLogoMark()
                .frame(width: 42, height: 42)
            Text("SiTV")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(SiTVTheme.text)
        }
        .frame(width: 96, height: 50)
        .opacity(0.8)
    }

    private func panelHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(SiTVTheme.text)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(SiTVTheme.textDim)
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
            beginFavoritePrompt()
        default:
            break
        }
    }

    private func handleTopActionMove(_ direction: MoveCommandDirection, target: FocusTarget) {
        panelHideTask?.cancel()
        switch (target, direction) {
        case (.refresh, .right):
            focusTarget = .settings
        case (.settings, .left):
            focusTarget = .refresh
        case (_, .down):
            focusCurrentChannel()
        default:
            focusTarget = target
        }
    }

    private func handleChannelMove(_ direction: MoveCommandDirection, channel: Channel) {
        touchPanel()
        guard let index = model.visibleChannels.firstIndex(where: { $0.id == channel.id }) else { return }
        switch direction {
        case .up:
            if index > 0 {
                focusTarget = .channel(model.visibleChannels[index - 1].id)
            } else {
                panelHideTask?.cancel()
                focusTarget = .refresh
            }
        case .down:
            if index + 1 < model.visibleChannels.count {
                focusTarget = .channel(model.visibleChannels[index + 1].id)
            }
        case .left:
            showGroupPanel()
        case .right:
            hidePanels()
        default:
            break
        }
    }

    private func handleGroupMove(_ direction: MoveCommandDirection, group: String) {
        touchPanel()
        guard let index = model.groups.firstIndex(of: group) else { return }
        switch direction {
        case .up:
            if index > 0 { focusTarget = .group(model.groups[index - 1]) }
        case .down:
            if index + 1 < model.groups.count { focusTarget = .group(model.groups[index + 1]) }
        case .left:
            showSourcePanel()
        case .right:
            showChannelPanel()
        default:
            break
        }
    }

    private func handleSourceMove(_ direction: MoveCommandDirection, slot: Int) {
        touchPanel()
        let sources = configuredSources
        guard let index = sources.firstIndex(where: { $0.slot == slot }) else { return }
        switch direction {
        case .up:
            if index > 0 { focusTarget = .source(sources[index - 1].slot) }
        case .down:
            if index + 1 < sources.count { focusTarget = .source(sources[index + 1].slot) }
        case .right:
            showGroupPanel()
        default:
            focusTarget = .source(slot)
        }
    }

    private func showChannelPanel() {
        favoritePromptChannelID = nil
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
        let configured = configuredSources
        guard !configured.isEmpty else {
            openSettings()
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

    private func openSettings() {
        panelHideTask?.cancel()
        favoritePromptChannelID = nil
        showSettings = true
    }

    private func touchPanel() {
        schedulePanelHide()
    }

    private func schedulePanelHide() {
        panelHideTask?.cancel()
        if focusTarget == .settings || focusTarget == .refresh || showSettings {
            return
        }
        panelHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !showSettings, focusTarget != .settings, focusTarget != .refresh {
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

    private func beginFavoritePrompt() {
        guard let channel = model.activeChannel else { return }
        panelHideTask?.cancel()
        infoHideTask?.cancel()
        infoVisible = false
        favoriteNotice = nil
        favoritePromptChannelID = channel.id
        DispatchQueue.main.async {
            focusTarget = .favoritePrompt
        }
    }

    private func commitFavoritePrompt() {
        guard let id = favoritePromptChannelID,
              let channel = model.channels.first(where: { $0.id == id }) else {
            dismissFavoritePrompt()
            return
        }
        favoritePromptChannelID = nil
        Task {
            await model.saveFavorite(channel)
            await MainActor.run {
                showFavoriteNotice(.saved)
            }
        }
    }

    private func dismissFavoritePrompt() {
        favoritePromptChannelID = nil
        restorePlayerFocus()
    }

    private func showFavoriteNotice(_ notice: FavoriteNotice) {
        favoriteNotice = notice
        restorePlayerFocus()
        infoHideTask?.cancel()
        infoHideTask = Task {
            try? await Task.sleep(for: .milliseconds(2_500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                favoriteNotice = nil
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
                panelHideTask?.cancel()
                focusTarget = .settings
            }
        }
    }

    private func restorePlayerFocus() {
        panelHideTask?.cancel()
        if panel == .hidden, !model.channels.isEmpty, favoritePromptChannelID == nil {
            DispatchQueue.main.async {
                focusTarget = .player
            }
        }
    }

    private var configuredSources: [PlaylistSource] {
        model.sources.filter(\.isConfigured)
    }

    private func channelCount(for group: String) -> Int {
        switch group {
        case "Tất cả":
            return model.channels.count
        case "KÊNH YÊU THÍCH ♥":
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

    private func channelBackground(focused: Bool, selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(focused ? SiTVTheme.cardFocus : (selected ? SiTVTheme.cardSelected : SiTVTheme.card))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        focused ? SiTVTheme.orange : (selected ? SiTVTheme.orange.opacity(0.6) : Color.clear),
                        lineWidth: focused ? 2 : (selected ? 1 : 0)
                    )
            }
    }

    private func groupBackground(_ group: String) -> some View {
        let focused = focusTarget == .group(group)
        let selected = model.selectedGroup == group
        return RoundedRectangle(cornerRadius: 18)
            .fill(focused ? SiTVTheme.orange : (selected ? SiTVTheme.groupSelected : SiTVTheme.groupCard))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(selected && !focused ? SiTVTheme.orange : Color.clear, lineWidth: 1)
            }
    }

    private func groupForeground(_ group: String) -> Color {
        focusTarget == .group(group) ? SiTVTheme.black : SiTVTheme.text
    }

    private func sourceBackground(_ source: PlaylistSource) -> some View {
        let focused = focusTarget == .source(source.slot)
        return RoundedRectangle(cornerRadius: 14)
            .fill(focused ? SiTVTheme.cardFocus : SiTVTheme.card)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(focused ? SiTVTheme.orange : Color.clear, lineWidth: 2)
            }
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
    case favoritePrompt
}

private enum FavoriteNotice {
    case saved

    var text: String {
        switch self {
        case .saved: return "Đã lưu kênh yêu thích"
        }
    }

    var heartColor: Color {
        switch self {
        case .saved: return Color(red: 230 / 255, green: 45 / 255, blue: 45 / 255)
        }
    }
}

private enum SiTVTheme {
    static let black = Color(red: 8 / 255, green: 10 / 255, blue: 13 / 255)
    static let panel = Color(red: 20 / 255, green: 23 / 255, blue: 28 / 255).opacity(0.91)
    static let sourcePanel = Color(red: 13 / 255, green: 16 / 255, blue: 20 / 255).opacity(0.94)
    static let groupPanel = Color(red: 17 / 255, green: 20 / 255, blue: 25 / 255).opacity(0.93)
    static let card = Color(red: 34 / 255, green: 38 / 255, blue: 45 / 255).opacity(0.80)
    static let cardFocus = Color(red: 56 / 255, green: 62 / 255, blue: 72 / 255).opacity(0.95)
    static let cardSelected = Color(red: 44 / 255, green: 49 / 255, blue: 57 / 255).opacity(0.84)
    static let groupCard = Color(red: 42 / 255, green: 47 / 255, blue: 55 / 255).opacity(0.65)
    static let groupSelected = Color(red: 77 / 255, green: 85 / 255, blue: 97 / 255).opacity(0.70)
    static let button = Color(red: 52 / 255, green: 58 / 255, blue: 68 / 255).opacity(0.80)
    static let orange = Color(red: 1, green: 138 / 255, blue: 42 / 255)
    static let text = Color(red: 1, green: 247 / 255, blue: 244 / 255)
    static let textDim = Color(red: 174 / 255, green: 183 / 255, blue: 194 / 255)
}

private struct SiTVLogoMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(SiTVTheme.orange)
            Image(systemName: "play.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 0.36 * 52, height: 0.36 * 52)
                .foregroundStyle(.white)
                .offset(x: 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    ContentView(model: AppModel())
}
