import Foundation

enum PlayerEngineKind: String, CaseIterable, Codable, Sendable {
    case avPlayer
    case vlc
    case dash
    case dashClearKey
}

struct PlaybackRequest: Hashable, Sendable {
    let channel: Channel
    let sourceIndex: Int
    let source: StreamSource
}

struct PlaybackAttempt: Hashable, Sendable {
    let sourceIndex: Int
    let engine: PlayerEngineKind
    let source: StreamSource
}

enum PlayerEngineError: Error, Equatable, Sendable {
    case unsupported
    case failedToStart(String)
    case stopped
}

extension PlayerEngineError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Luồng này chưa được SiTV hỗ trợ trên Apple TV."
        case let .failedToStart(reason):
            let detail = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "Không thể bắt đầu phát kênh."
                : "Không thể bắt đầu phát kênh: \(detail)"
        case .stopped:
            return "Phát kênh đã dừng."
        }
    }
}

protocol PlayerEngine: AnyObject {
    var kind: PlayerEngineKind { get }
    func canPlay(_ source: StreamSource) -> Bool
    func start(_ request: PlaybackRequest) async throws
    func stop() async
}
