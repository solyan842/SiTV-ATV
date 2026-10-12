import Foundation

protocol PlaylistDecoding: Sendable {
    func decode(_ data: Data) throws -> String
}

struct UTF8PlaylistDecoder: PlaylistDecoding {
    func decode(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PlaylistRepositoryError.invalidEncoding
        }
        return text
    }
}
