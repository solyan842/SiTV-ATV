import Foundation

struct PlaylistSource: Codable, Equatable, Identifiable, Sendable {
    let slot: Int
    var name: String
    var url: String

    var id: Int { slot }

    var isConfigured: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
