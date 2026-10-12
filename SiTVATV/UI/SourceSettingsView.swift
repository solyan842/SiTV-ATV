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
        Form {
            ForEach(drafts.indices, id: \.self) { index in
                Section("Nguồn \(index + 1)") {
                    TextField("Tên nguồn", text: binding(for: index, keyPath: \.name))
                    TextField("URL M3U", text: binding(for: index, keyPath: \.url))
                        .textInputAutocapitalization(.never)

                    Button(activeSlot == index ? "Đang sử dụng" : "Đặt làm nguồn đang dùng") {
                        activeSlot = index
                    }
                    .disabled(!drafts[index].isConfigured || activeSlot == index)
                }
            }

            Section {
                Button("Lưu và tải playlist") {
                    Task {
                        await model.saveSources(drafts, activeSlot: activeSlot)
                        if model.errorMessage == nil {
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle("Nguồn IPTV")
    }

    private func binding(for index: Int, keyPath: WritableKeyPath<PlaylistSource, String>) -> Binding<String> {
        Binding(
            get: { drafts[index][keyPath: keyPath] },
            set: { drafts[index][keyPath: keyPath] = $0 }
        )
    }
}
