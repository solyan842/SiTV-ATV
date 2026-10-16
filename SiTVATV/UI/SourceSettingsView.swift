import SwiftUI

struct SourceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel

    @State private var drafts: [PlaylistSource]
    @State private var activeSlot: Int
    @FocusState private var focusTarget: SettingsFocus?

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
                    HStack(alignment: .center, spacing: 18) {
                        ZStack {
                            Circle().fill(SettingsTheme.orange)
                            Image(systemName: "play.fill")
                                .font(.system(size: 25, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 2)
                        }
                        .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nguồn IPTV")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(SettingsTheme.text)
                            Text("Tối đa 5 playlist · nhập xong URL sẽ chuyển thẳng tới Lưu")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(SettingsTheme.textDim)
                        }
                    }
                    .padding(.bottom, 24)

                    VStack(spacing: 14) {
                        ForEach(drafts.indices, id: \.self) { index in
                            sourceRow(index)
                        }
                    }

                    HStack(spacing: 18) {
                        settingsButton(
                            title: model.isLoading ? "Đang lưu…" : "Lưu nguồn IPTV",
                            systemImage: "checkmark.circle.fill",
                            focus: .save,
                            enabled: !model.isLoading && hasConfiguredSource
                        ) {
                            saveAndDismiss()
                        }

                        settingsButton(
                            title: "Đóng",
                            systemImage: "xmark.circle",
                            focus: .close,
                            enabled: true
                        ) {
                            dismiss()
                        }
                    }
                    .frame(height: 62)
                    .padding(.top, 22)
                }
                .frame(width: 1060)
                .padding(.top, 48)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            let slot = drafts.indices.contains(activeSlot) ? activeSlot : 0
            DispatchQueue.main.async {
                focusTarget = .name(slot)
            }
        }
    }

    private func sourceRow(_ index: Int) -> some View {
        let rowFocused = focusBelongsToRow(index)

        return HStack(spacing: 14) {
            Text("\(index + 1)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(SettingsTheme.orange)
                .frame(width: 42, height: 42)
                .background(SettingsTheme.orange.opacity(0.12), in: Circle())

            TextField("Tên nguồn", text: binding(for: index, keyPath: \.name))
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SettingsTheme.text)
                .padding(.horizontal, 16)
                .frame(width: 230, height: 62)
                .background(fieldBackground(focused: focusTarget == .name(index)))
                .focused($focusTarget, equals: .name(index))
                .focusEffectDisabled()
                .submitLabel(.next)
                .onSubmit {
                    focusTarget = .url(index)
                }

            TextField("https://playlist.m3u", text: binding(for: index, keyPath: \.url))
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(SettingsTheme.text)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62)
                .background(fieldBackground(focused: focusTarget == .url(index)))
                .focused($focusTarget, equals: .url(index))
                .focusEffectDisabled()
                .submitLabel(.done)
                .onSubmit {
                    moveToSaveIfPossible()
                }
                .onMoveCommand { direction in
                    if direction == .down {
                        moveToSaveIfPossible()
                    }
                }

            Button {
                if drafts[index].isConfigured {
                    activeSlot = index
                }
            } label: {
                Image(systemName: activeSlot == index ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(activeSlot == index ? SettingsTheme.orange : SettingsTheme.textDim)
                    .frame(width: 58, height: 58)
                    .background(buttonBackground(focused: focusTarget == .active(index)))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(!drafts[index].isConfigured)
            .focused($focusTarget, equals: .active(index))

            Button {
                clearDraft(index)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 58, height: 58)
                    .background(buttonBackground(focused: focusTarget == .clear(index)))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(!drafts[index].isConfigured && drafts[index].name.isEmpty && drafts[index].url.isEmpty)
            .focused($focusTarget, equals: .clear(index))
        }
        .padding(.horizontal, 18)
        .frame(height: 82)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(rowFocused ? SettingsTheme.rowFocused : SettingsTheme.row)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(rowFocused ? SettingsTheme.orange.opacity(0.85) : SettingsTheme.border, lineWidth: rowFocused ? 2 : 1)
                }
        )
    }

    private func settingsButton(
        title: String,
        systemImage: String,
        focus: SettingsFocus,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let focused = focusTarget == focus
        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(enabled ? SettingsTheme.text : SettingsTheme.textDim.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(focused ? SettingsTheme.buttonFocused : SettingsTheme.button)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(focused ? SettingsTheme.orange : SettingsTheme.border, lineWidth: focused ? 3 : 1)
                        }
                )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(!enabled)
        .focused($focusTarget, equals: focus)
    }

    private func fieldBackground(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(SettingsTheme.field)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(focused ? SettingsTheme.orange : SettingsTheme.border, lineWidth: focused ? 3 : 1)
            }
    }

    private func buttonBackground(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(focused ? SettingsTheme.buttonFocused : SettingsTheme.button)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(focused ? SettingsTheme.orange : SettingsTheme.border, lineWidth: focused ? 3 : 1)
            }
    }

    private func focusBelongsToRow(_ index: Int) -> Bool {
        switch focusTarget {
        case .clear(let value), .name(let value), .url(let value), .active(let value):
            return value == index
        default:
            return false
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
        focusTarget = .name(index)
    }

    private func normalizeActiveSlot() {
        if drafts.indices.contains(activeSlot), drafts[activeSlot].isConfigured {
            return
        }
        if let first = drafts.first(where: \.isConfigured) {
            activeSlot = first.slot
        }
    }

    private func moveToSaveIfPossible() {
        normalizeActiveSlot()
        if hasConfiguredSource {
            focusTarget = .save
        }
    }

    private func saveAndDismiss() {
        Task {
            normalizeActiveSlot()
            await model.saveSources(drafts, activeSlot: activeSlot)
            dismiss()
        }
    }

    private func binding(for index: Int, keyPath: WritableKeyPath<PlaylistSource, String>) -> Binding<String> {
        Binding(
            get: { drafts[index][keyPath: keyPath] },
            set: { drafts[index][keyPath: keyPath] = $0 }
        )
    }
}

private enum SettingsFocus: Hashable {
    case clear(Int)
    case name(Int)
    case url(Int)
    case active(Int)
    case save
    case close
}

private enum SettingsTheme {
    static let black = Color(red: 7 / 255, green: 9 / 255, blue: 12 / 255)
    static let row = Color(red: 18 / 255, green: 22 / 255, blue: 28 / 255).opacity(0.97)
    static let rowFocused = Color(red: 24 / 255, green: 29 / 255, blue: 37 / 255).opacity(0.99)
    static let field = Color(red: 30 / 255, green: 35 / 255, blue: 43 / 255)
    static let button = Color(red: 31 / 255, green: 36 / 255, blue: 44 / 255)
    static let buttonFocused = Color(red: 42 / 255, green: 48 / 255, blue: 58 / 255)
    static let border = Color.white.opacity(0.10)
    static let orange = Color(red: 1, green: 138 / 255, blue: 42 / 255)
    static let text = Color(red: 1, green: 247 / 255, blue: 244 / 255)
    static let textDim = Color(red: 174 / 255, green: 183 / 255, blue: 194 / 255)
}
