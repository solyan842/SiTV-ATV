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

    private let panelVisibleSeconds: Double = 8
    private let infoVisibleSeconds: Double = 8

    var body: some View {
        ZStack(alignment: .topLeading) {
            playbackBackground

            if model.channels.isEmpty, !model.isLoading {
                setupState
            }

            if infoVisible,
               let channel = model.activeChannel,
               panel == .hidden,
               favoritePromptChannelID == nil {
                nowPlaying(channel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 34)
                    .padding(.trailing, 42)
                    .allowsHitTesting(false)

                brandOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(30)
                    .allowsHitTesting(false)
            }

            if panel != .hidden {
                navigationPanels
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(20)
            }

            if panel == .hidden,
               !model.channels.isEmpty,
               favoritePromptChannelID == nil {
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
                    .padding(30)
                    .background(SiTVTheme.cardStrong, in: RoundedRectangle(cornerRadius: 20))
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
        .onChange(of: focusTarget) { _, _ in
            if panel != .hidden {
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
        VStack(spacing: 24) {
            SiTVLogoMark()
                .frame(width: 112, height: 112)

            Text("SiTV")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(SiTVTheme.text)

            Text(model.activeSource.isConfigured ? "Chưa có danh sách kênh" : "Chưa cấu hình nguồn IPTV")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(SiTVTheme.textDim)

            Button {
                panelHideTask?.cancel()
                showSettings = true
            } label: {
                Label("Nguồn IPTV", systemImage: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.horizontal, 24)
                    .frame(height: 60)
                    .background(SiTVTheme.orange, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var remoteCapture: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .focused($focusTarget, equals: .player)
            .onMoveCommand { direction in
                handlePlayerMove(direction)
            }
            .onPlayPauseCommand {
                showChannelPanel()
            }
            .onExitCommand {
                // MENU / Back while watching must reveal the channel list rather
                // than allowing tvOS to leave the app immediately.
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
                .frame(width: 560)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: panel)
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelHeader("Nguồn IPTV", subtitle: "↑ ↓ chọn nguồn  •  OK tải  •  → nhóm")

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(configuredSources) { source in
                        let target = FocusTarget.source(source.slot)
                        let focused = focusTarget == target
                        let selected = source.slot == model.activeSource.slot

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
                            HStack(spacing: 14) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(selected ? SiTVTheme.orange : SiTVTheme.textDim)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(source.name.isEmpty ? "Nguồn \(source.slot + 1)" : source.name)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(SiTVTheme.text)
                                        .lineLimit(1)
                                    Text(source.url)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(SiTVTheme.textDim)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                            .background(cardBackground(focused: focused, selected: selected, radius: 18))
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .focused($focusTarget, equals: target)
                        .onMoveCommand { direction in
                            handleSourceMove(direction, slot: source.slot)
                        }
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
            }

            Text("@2026 SolYan-SiTV")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SiTVTheme.textDim)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.top, 32)
        .padding(.bottom, 22)
        .background(SiTVTheme.sourcePanel)
        .onExitCommand {
            showGroupPanel()
        }
    }

    private var groupPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelHeader("Nhóm kênh", subtitle: "← nguồn  •  ↑ ↓ chọn  •  → kênh")

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.groups, id: \.self) { group in
                        let target = FocusTarget.group(group)
                        let focused = focusTarget == target
                        let selected = model.selectedGroup == group

                        Button {
                            touchPanel()
                            model.selectGroup(group)
                            panel = .channels
                            focusCurrentChannel()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: group == "KÊNH YÊU THÍCH ♥" ? "heart.fill" : "square.grid.2x2.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(group == "KÊNH YÊU THÍCH ♥" ? .red : SiTVTheme.orange)
                                    .frame(width: 32)

                                Text(group)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(SiTVTheme.text)
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Text("\(channelCount(for: group))")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(SiTVTheme.textDim)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 68)
                            .background(cardBackground(focused: focused, selected: selected, radius: 18))
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .focused($focusTarget, equals: target)
                        .onMoveCommand { direction in
                            handleGroupMove(direction, group: group)
                        }
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 32)
        .padding(.bottom, 22)
        .background(SiTVTheme.groupPanel)
        .onExitCommand {
            showChannelPanel()
        }
    }

    private var channelPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                SiTVLogoMark()
                    .frame(width: 68, height: 68)

                VStack(alignment: .leading, spacing: 3) {
                    Text("SiTV")
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(SiTVTheme.text)
                    Text(model.activeSource.name.isEmpty ? "Nguồn IPTV" : model.activeSource.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SiTVTheme.textDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 76)

            HStack(spacing: 14) {
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
            .frame(height: 58)

            HStack {
                Text("DANH SÁCH KÊNH")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SiTVTheme.textDim)
                Spacer()
                Text("← Nhóm kênh")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SiTVTheme.orange.opacity(0.92))
            }
            .padding(.horizontal, 8)

            if model.visibleChannels.isEmpty {
                VStack(spacing: 18) {
                    Spacer()
                    Image(systemName: "tv.slash")
                        .font(.system(size: 46))
                        .foregroundStyle(SiTVTheme.textDim)
                    Text(model.isFavoritesSelected ? "Chưa có kênh yêu thích" : "Nhóm này chưa có kênh")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SiTVTheme.textDim)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(model.visibleChannels) { channel in
                                channelRow(channel)
                                    .id(channel.id)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                    }
                    .onChange(of: model.activeChannel?.id) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.14)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Text("\(model.visibleChannels.count)/\(model.channels.count) kênh")
                    .lineLimit(1)
                Spacer(minLength: 10)
                if model.isPlaybackStarting, let channel = model.activeChannel {
                    Label("Đang mở · \(channel.name)", systemImage: "hourglass")
                        .lineLimit(1)
                } else if let attempt = model.activeAttempt {
                    Text("\(attempt.engine.rawValue) · nguồn \(attempt.sourceIndex + 1)")
                        .lineLimit(1)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(SiTVTheme.textDim)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 30,
                topTrailingRadius: 30
            )
            .fill(SiTVTheme.panel)
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SiTVTheme.orange.opacity(0.75))
                .frame(width: 2)
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
            HStack(spacing: 15) {
                Text(channelNumberText(channel))
                    .font(.system(size: 21, weight: .bold, design: .monospaced))
                    .foregroundStyle(SiTVTheme.orange)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 54, alignment: .leading)

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.28))
                    AsyncImage(url: channel.logoURL.flatMap(URL.init(string:))) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "tv")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(SiTVTheme.textDim)
                            .padding(14)
                    }
                    .padding(6)
                }
                .frame(width: 92, height: 64)
                .clipped()

                VStack(alignment: .leading, spacing: 5) {
                    Text(channel.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(SiTVTheme.text)
                        .lineLimit(1)
                    Text(channel.group)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SiTVTheme.textDim)
                        .lineLimit(1)
                }

                Spacer(minLength: 5)

                if model.isFavorite(channel) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 17, weight: .bold))
                }

                if selected {
                    ZStack {
                        Circle().fill(SiTVTheme.orange.opacity(0.18))
                        Image(systemName: "play.fill")
                            .foregroundStyle(SiTVTheme.orange)
                            .font(.system(size: 17, weight: .bold))
                            .offset(x: 1)
                    }
                    .frame(width: 38, height: 38)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 94)
            .background(channelBackground(focused: focused, selected: selected))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
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
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(SiTVTheme.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardBackground(focused: focused, selected: false, radius: 16))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
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
        .focusEffectDisabled()
        .focused($focusTarget, equals: .favoritePrompt)
        .overlay(alignment: .topTrailing) {
            favoriteBanner(heartColor: .white, text: "Lưu kênh yêu thích")
                .padding(34)
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
            .padding(34)
            .allowsHitTesting(false)
    }

    private func favoriteBanner(heartColor: Color, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "heart.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(heartColor)
            Text(text)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(SiTVTheme.text)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(SiTVTheme.overlay, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func nowPlaying(_ channel: Channel) -> some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.30))
                AsyncImage(url: channel.logoURL.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "tv")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(SiTVTheme.textDim)
                        .padding(18)
                }
                .padding(7)
            }
            .frame(width: 108, height: 76)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(model.activeChannelNumber.map { String(format: "%02d", $0) } ?? "--")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(SiTVTheme.orange)
                    Text(channel.name)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(SiTVTheme.text)
                        .lineLimit(1)
                }

                Text(channel.group)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SiTVTheme.textDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 17)
        .frame(minWidth: 430, alignment: .leading)
        .background(SiTVTheme.overlay, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var brandOverlay: some View {
        HStack(spacing: 8) {
            SiTVLogoMark()
                .frame(width: 48, height: 48)
            Text("SiTV")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(SiTVTheme.text)
        }
        .opacity(0.82)
    }

    private func panelHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(SiTVTheme.text)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SiTVTheme.textDim)
        }
    }

    private func handlePlayerMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            showChannelPanel()
        case .up:
            Task {
                await model.stepChannel(1)
                await MainActor.run { showNowInfo() }
            }
        case .down:
            Task {
                await model.stepChannel(-1)
                await MainActor.run { showNowInfo() }
            }
        case .right:
            beginFavoritePrompt()
        default:
            break
        }
    }

    private func handleTopActionMove(_ direction: MoveCommandDirection, target: FocusTarget) {
        touchPanel()
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
        guard !showSettings else { return }
        panelHideTask = Task {
            try? await Task.sleep(for: .seconds(panelVisibleSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !showSettings else { return }
                panel = .hidden
                restorePlayerFocus()
            }
        }
    }

    private func showNowInfo() {
        infoHideTask?.cancel()
        infoVisible = true
        infoHideTask = Task {
            try? await Task.sleep(for: .seconds(infoVisibleSeconds))
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
            try? await Task.sleep(for: .seconds(4))
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
        RoundedRectangle(cornerRadius: 19)
            .fill(focused ? SiTVTheme.cardFocus : (selected ? SiTVTheme.cardSelected : SiTVTheme.card))
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(SiTVTheme.orange)
                        .frame(width: 5, height: 54)
                        .padding(.leading, 3)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 19)
                    .stroke(
                        focused ? SiTVTheme.orange : (selected ? SiTVTheme.orange.opacity(0.55) : SiTVTheme.border),
                        lineWidth: focused ? 3 : 1
                    )
            }
    }

    private func cardBackground(focused: Bool, selected: Bool, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(focused ? SiTVTheme.cardFocus : (selected ? SiTVTheme.cardSelected : SiTVTheme.card))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(
                        focused ? SiTVTheme.orange : (selected ? SiTVTheme.orange.opacity(0.55) : SiTVTheme.border),
                        lineWidth: focused ? 3 : 1
                    )
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
    static let black = Color(red: 6 / 255, green: 8 / 255, blue: 11 / 255)
    static let panel = Color(red: 13 / 255, green: 17 / 255, blue: 22 / 255).opacity(0.97)
    static let sourcePanel = Color(red: 9 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.985)
    static let groupPanel = Color(red: 11 / 255, green: 14 / 255, blue: 19 / 255).opacity(0.98)
    static let card = Color(red: 28 / 255, green: 33 / 255, blue: 41 / 255).opacity(0.90)
    static let cardStrong = Color(red: 24 / 255, green: 29 / 255, blue: 36 / 255).opacity(0.98)
    static let cardFocus = Color(red: 39 / 255, green: 46 / 255, blue: 57 / 255).opacity(0.99)
    static let cardSelected = Color(red: 34 / 255, green: 40 / 255, blue: 49 / 255).opacity(0.96)
    static let overlay = Color(red: 8 / 255, green: 11 / 255, blue: 15 / 255).opacity(0.88)
    static let border = Color.white.opacity(0.08)
    static let orange = Color(red: 1, green: 138 / 255, blue: 42 / 255)
    static let text = Color(red: 1, green: 247 / 255, blue: 244 / 255)
    static let textDim = Color(red: 174 / 255, green: 183 / 255, blue: 194 / 255)
}

private struct SiTVLogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(SiTVTheme.orange)
                Image(systemName: "play.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: side * 0.38, height: side * 0.38)
                    .foregroundStyle(.white)
                    .offset(x: side * 0.035)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    ContentView(model: AppModel())
}
