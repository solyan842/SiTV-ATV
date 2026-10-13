import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(model.groups, id: \.self) { group in
                    Button {
                        model.selectedGroup = group
                    } label: {
                        HStack {
                            if group == "Yêu thích" {
                                Image(systemName: "star.fill")
                            }
                            Text(group)
                            Spacer()
                            if model.selectedGroup == group {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Nhóm kênh")
        } detail: {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()

                if model.channels.isEmpty {
                    emptyState
                } else if model.visibleChannels.isEmpty {
                    filteredEmptyState
                } else {
                    channelGrid
                }

                Button {
                    showSettings = true
                } label: {
                    Label("Cài đặt", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .padding(.top, 20)
                .padding(.trailing, 36)
            }
            .navigationTitle(model.activeSource.name.isEmpty ? "SiTV" : model.activeSource.name)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SourceSettingsView(model: model)
            }
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

    private var emptyState: some View {
        VStack(spacing: 24) {
            if model.isLoading {
                ProgressView()
                Text("Đang tải playlist…")
            } else {
                Image(systemName: "tv")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Chưa có danh sách kênh")
                    .font(.title2)
                Button("Nhập URL M3U") {
                    showSettings = true
                }
            }
        }
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: model.isFavoritesSelected ? "star" : "rectangle.grid.2x2")
                .font(.system(size: 58))
                .foregroundStyle(.secondary)
            Text(model.isFavoritesSelected ? "Chưa có kênh yêu thích" : "Nhóm này chưa có kênh")
                .font(.title2)
            if model.isFavoritesSelected {
                Text("Nhấn biểu tượng ngôi sao ở một kênh để thêm vào Yêu thích.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(48)
    }

    private var channelGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 24)], spacing: 24) {
                ForEach(model.visibleChannels) { channel in
                    HStack(spacing: 12) {
                        Button {
                            Task { await model.play(channel) }
                        } label: {
                            HStack(spacing: 18) {
                                AsyncImage(url: channel.logoURL.flatMap(URL.init(string:))) { image in
                                    image
                                        .resizable()
                                        .scaledToFit()
                                } placeholder: {
                                    Image(systemName: "tv")
                                        .font(.title)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 86, height: 64)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(channel.name)
                                        .font(.headline)
                                        .lineLimit(2)
                                    Text(channel.group)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, minHeight: 100)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await model.toggleFavorite(channel) }
                        } label: {
                            Image(systemName: model.isFavorite(channel) ? "star.fill" : "star")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(
                            model.isFavorite(channel) ? "Bỏ khỏi Yêu thích" : "Thêm vào Yêu thích"
                        )
                    }
                }
            }
            .padding(36)
        }
    }
}

#Preview {
    ContentView(model: AppModel())
}
