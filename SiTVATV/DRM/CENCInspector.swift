import CMAFKit
import Foundation

struct CENCTrackInfo: Sendable, Equatable {
    let trackID: UInt32
    let kind: CMAFTrackKind
    let scheme: CommonEncryptionScheme
    let keyID: Data
    let perSampleIVSize: UInt8
    let constantIV: Data?
    let cryptByteBlock: UInt8
    let skipByteBlock: UInt8
}

struct CENCInspection: Sendable, Equatable {
    let tracks: [CENCTrackInfo]

    var isProtected: Bool {
        !tracks.isEmpty
    }
}

enum CENCInspectorError: Error, Equatable {
    case keyIDMismatch
}

struct CMAFCENCInspector {
    func inspect(initSegment data: Data) async throws -> CENCInspection {
        let reader = try await CMAFInitSegmentReader(bytes: data)
        return inspect(tracks: reader.tracks())
    }

    func inspect(tracks: [CMAFTrackConfiguration]) -> CENCInspection {
        let protectedTracks = tracks.compactMap { track -> CENCTrackInfo? in
            guard let encryption = track.encryptionParameters else {
                return nil
            }

            return CENCTrackInfo(
                trackID: track.trackID,
                kind: track.kind,
                scheme: encryption.scheme,
                keyID: encryption.defaultKID.rawBytes,
                perSampleIVSize: encryption.defaultPerSampleIVSize.rawValue,
                constantIV: encryption.defaultConstantIV?.rawBytes,
                cryptByteBlock: encryption.defaultCryptByteBlock,
                skipByteBlock: encryption.defaultSkipByteBlock
            )
        }
        return CENCInspection(tracks: protectedTracks)
    }

    func validate(
        material: ClearKeyMaterial,
        for track: CENCTrackInfo
    ) throws {
        guard material.keyID == track.keyID else {
            throw CENCInspectorError.keyIDMismatch
        }
    }
}
