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
            SettingsTheme.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SiTV · Cài đặt")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(SettingsTheme.text)

                    Text("Nguồn IPTV · đặt tên và lưu tối đa 5 URL")
                        .font(.system(size: 15))
                        .foregroundStyle(SettingsTheme.textDim)
                        .padding(.top, 18)

                    VStack(spacing: 10) {
                        ForEach(drafts.indices, id: \.self) { index in
                            sourceRow(index)
                        }
                    }
                    .padding(.top, 12)

                    HStack(spacing: 16) {
                        Button {
                            Task {
                                normalizeActiveSlot()
                                await model.saveSources(drafts, activeSlot: activeSlot)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if model.isLoading {
                                    ProgressView()
                                }
                                Text("Lưu nguồn IPTV")
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(SiTVSettingsButtonStyle())
                        .disabled(model.isLoading || !hasConfiguredSource)

                        Button {
                            dismiss()
                        } label: {
                            Text("Đóng")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(SiTVSettingsButtonStyle())
                    }
                    .padding(.top, 18)
                }
                .frame(width: 820)
                .padding(.top, 34)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func sourceRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                clearDraft(index)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(SiTVSettingsButtonStyle())
            .disabled(!drafts[index].isConfigured && drafts[index].name.isEmpty && drafts[index].url.isEmpty)

            TextField("Tên nguồn \(index + 1)", text: binding(for: index, keyPath: \.name))
                .textFieldStyle(.plain)
                .foregroundStyle(SettingsTheme.text)
                .padding(.horizontal, 14)
                .frame(width: 180, height: 58)
                .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 14))

            TextField("https://...", text: binding(for: index, keyPath: \.url))
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .foregroundStyle(SettingsTheme.text)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58)
                .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 14))

            Button {
                if drafts[index].isConfigured {
                    activeSlot = index
                }
            } label: {
                Image(systemName: activeSlot == index ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(activeSlot == index ? SettingsTheme.orange : SettingsTheme.textDim)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(SiTVSettingsButtonStyle())
            .disabled(!drafts[index].isConfigured)
            .accessibilityLabel(activeSlot == index ? "Nguồn đang dùng" : "Chọn nguồn \(index + 1)")
        }
        .frame(height: 58)
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

private struct SiTVSettingsButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(SettingsTheme.text)
            .background(
                isFocused ? SettingsTheme.orange : SettingsTheme.button,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .scaleEffect(isFocused ? 1.035 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private enum SettingsTheme {
    static let black = Color(red: 8 / 255, green: 10 / 255, blue: 13 / 255)
    static let card = Color(red: 34 / 255, green: 38 / 255, blue: 45 / 255).opacity(0.80)
    static let button = Color(red: 52 / 255, green: 58 / 255, blue: 68 / 255).opacity(0.80)
    static let orange = Color(red: 1, green: 138 / 255, blue: 42 / 255)
    static let text = Color(red: 1, green: 247 / 255, blue: 244 / 255)
    static let textDim = Color(red: 174 / 255, green: 183 / 255, blue: 194 / 255)
}
