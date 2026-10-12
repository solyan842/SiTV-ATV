import SwiftUI

struct SourceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel

    @State private var name: String
    @State private var url: String

    init(model: AppModel) {
        self.model = model
        _name = State(initialValue: model.activeSource.name)
        _url = State(initialValue: model.activeSource.url)
    }

    var body: some View {
        Form {
            Section("Nguồn IPTV") {
                TextField("Tên nguồn", text: $name)
                TextField("URL M3U", text: $url)
                    .textInputAutocapitalization(.never)
            }

            Section {
                Button("Lưu và tải playlist") {
                    Task {
                        await model.configurePrimarySource(name: name, url: url)
                        if model.errorMessage == nil {
                            dismiss()
                        }
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Cài đặt")
    }
}
