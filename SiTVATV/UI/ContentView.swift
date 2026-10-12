import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedGroup) {
                ForEach(model.groups, id: \.self) { group in
                    Text(group)
                        .tag(group)
                }
            }
            .navigationTitle("Nhóm kênh")
        } detail: {
            ZStack {
                Color.black.ignoresSafeArea()

                if model.channels.isEmpty {
                    emptyState
                } else {
                    channelGrid
                }
            }
            .navigationTitle(model.activeSource.name.isEmpty ? "SiTV" : model.activeSource.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Cài đặt", systemImage: "gearshape")
                    }
                }
            }
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

    private var channelGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24)], spacing: 24) {
                ForEach(model.visibleChannels) { channel in
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
                }
            }
            .padding(36)
        }
    }
}

#Preview {
    ContentView(model: AppModel())
}
