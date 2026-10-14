import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 350)

                Divider()
                    .overlay(Color.white.opacity(0.12))

                VStack(spacing: 0) {
                    topBar

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showSettings) {
            SourceSettingsView(model: model)
        }
        .fullScreenCover(isPresented: $model.isPlayerPresented) {
            PlayerView(model: model)
        }
        .alert("SiTV", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SiTV")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("Truyền hình trực tuyến")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.groups, id: \.self) { group in
                        Button {
                            model.selectedGroup = group
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: group == "Yêu thích" ? "star.fill" : "square.grid.2x2")
                                    .frame(width: 28)

                                Text(group)
                                    .lineLimit(1)

                                Spacer(minLength: 12)

                                Text("\(channelCount(for: group))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 18)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(
                                model.selectedGroup == group
                                    ? Color.white.opacity(0.14)
                                    : Color.white.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.white.opacity(0.035))
    }

    private var topBar: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.selectedGroup)
                    .font(.title2.weight(.semibold))

                if model.activeSource.isConfigured {
                    Text(model.activeSource.name.isEmpty ? "Nguồn IPTV" : model.activeSource.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Chưa cấu hình playlist")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if model.isLoading {
                ProgressView()
            }

            Button {
                showSettings = true
            } label: {
                Label("Nguồn IPTV", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var content: some View {
        if model.channels.isEmpty {
            emptyState
        } else if model.visibleChannels.isEmpty {
            filteredEmptyState
        } else {
            channelGrid
        }
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()

            if model.isLoading {
                ProgressView()
                Text("Đang tải playlist…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "tv")
                    .font(.system(size: 68))
                    .foregroundStyle(.secondary)

                Text("Chưa có danh sách kênh")
                    .font(.title2.weight(.semibold))

                Text("Thêm URL M3U để bắt đầu.")
                    .foregroundStyle(.secondary)

                Button("Thêm playlist") {
                    showSettings = true
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: model.isFavoritesSelected ? "star" : "rectangle.grid.2x2")
                .font(.system(size: 62))
                .foregroundStyle(.secondary)

            Text(model.isFavoritesSelected ? "Chưa có kênh yêu thích" : "Nhóm này chưa có kênh")
                .font(.title2.weight(.semibold))

            if model.isFavoritesSelected {
                Text("Chọn ngôi sao trên thẻ kênh để thêm vào Yêu thích.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }

    private var channelGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320, maximum: 390), spacing: 28)],
                spacing: 28
            ) {
                ForEach(model.visibleChannels) { channel in
                    channelCard(channel)
                }
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 32)
        }
    }

    private func channelCard(_ channel: Channel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                AsyncImage(url: channel.logoURL.flatMap(URL.init(string:))) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Image(systemName: "tv")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 96, height: 72)

                VStack(alignment: .leading, spacing: 7) {
                    Text(channel.name)
                        .font(.headline)
                        .lineLimit(2)

                    Text(channel.group.isEmpty ? "Truyền hình" : channel.group)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    Task { await model.toggleFavorite(channel) }
                } label: {
                    Image(systemName: model.isFavorite(channel) ? "star.fill" : "star")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    model.isFavorite(channel) ? "Bỏ khỏi Yêu thích" : "Thêm vào Yêu thích"
                )
            }

            Button {
                Task { await model.play(channel) }
            } label: {
                Label("Phát", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(
            Color.white.opacity(0.065),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func channelCount(for group: String) -> Int {
        switch group {
        case "Tất cả":
            model.channels.count
        case "Yêu thích":
            model.channels.filter { model.favoriteChannelIDs.contains($0.id) }.count
        default:
            model.channels.filter { $0.group == group }.count
        }
    }
}

#Preview {
    ContentView(model: AppModel())
}
