import SwiftUI

struct SourceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel

    @State private var drafts: [PlaylistSource]
    @State private var activeSlot: Int

    init(model: AppModel) {
        self.model = model
        let initial = model.sources.count == PlaylistRepository.sourceCount
            ? model.sources
            : (0..<PlaylistRepository.sourceCount).map { PlaylistSource(slot: $0, name: "", url: "") }
        _drafts = State(initialValue: initial)
        _activeSlot = State(initialValue: model.activeSource.slot)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    header

                    ForEach(drafts.indices, id: \.self) { index in
                        sourceCard(index)
                    }

                    Button {
                        Task {
                            normalizeActiveSlot()
                            await model.saveSources(drafts, activeSlot: activeSlot)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            if model.isLoading {
                                ProgressView()
                            }
                            Label("Lưu và tải playlist", systemImage: "arrow.down.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoading || !hasConfiguredSource)
                    .padding(.top, 8)
                }
                .frame(maxWidth: 980)
                .padding(.horizontal, 48)
                .padding(.vertical, 36)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nguồn IPTV")
                    .font(.largeTitle.weight(.bold))
                Text("Tối đa 5 playlist. Có thể quay lại màn này bất cứ lúc nào từ Danh sách kênh → Cài đặt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("Đóng", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
        }
    }

    private func sourceCard(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Text("Nguồn \(index + 1)")
                    .font(.title3.weight(.semibold))

                if activeSlot == index {
                    Label("Đang dùng", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if drafts[index].isConfigured {
                    Button(activeSlot == index ? "Đã chọn" : "Chọn nguồn này") {
                        activeSlot = index
                    }
                    .buttonStyle(.bordered)
                    .disabled(activeSlot == index)
                }

                Button(role: .destructive) {
                    clearDraft(index)
                } label: {
                    Label("Xóa", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(!drafts[index].isConfigured && drafts[index].name.isEmpty && drafts[index].url.isEmpty)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tên nguồn")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Ví dụ: SiTV chính", text: binding(for: index, keyPath: \.name))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("URL M3U")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://example.com/playlist.m3u", text: binding(for: index, keyPath: \.url))
                    .textInputAutocapitalization(.never)
            }
        }
        .padding(24)
        .background(
            Color.white.opacity(activeSlot == index ? 0.095 : 0.055),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(activeSlot == index ? 0.20 : 0.08), lineWidth: 1)
        }
    }

    private var hasConfiguredSource: Bool {
        drafts.contains(where: \.isConfigured)
    }

    private func clearDraft(_ index: Int) {
        drafts[index] = PlaylistSource(slot: index, name: "", url: "")
        if activeSlot == index {
            normalizeActiveSlot()
        }
    }

    private func normalizeActiveSlot() {
        if drafts.indices.contains(activeSlot), drafts[activeSlot].isConfigured {
            return
        }
        if let first = drafts.first(where: \.isConfigured) {
            activeSlot = first.slot
        }
    }

    private func binding(for index: Int, keyPath: WritableKeyPath<PlaylistSource, String>) -> Binding<String> {
        Binding(
            get: { drafts[index][keyPath: keyPath] },
            set: { drafts[index][keyPath: keyPath] = $0 }
        )
    }
}
