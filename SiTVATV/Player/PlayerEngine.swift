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

protocol PlayerEngine: AnyObject {
    var kind: PlayerEngineKind { get }
    func canPlay(_ source: StreamSource) -> Bool
    func start(_ request: PlaybackRequest) async throws
    func stop() async
}
