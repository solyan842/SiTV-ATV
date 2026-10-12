import Foundation

enum ClearKeyError: Error, Equatable, Sendable {
    case missingKey
    case invalidFormat
    case invalidKeyID
    case invalidKey
}

struct ClearKeyMaterial: Hashable, Sendable {
    let keyID: Data
    let key: Data
}

protocol ClearKeyProviding: Sendable {
    func material(for source: StreamSource) throws -> ClearKeyMaterial
}

struct PlaylistClearKeyProvider: ClearKeyProviding {
    func material(for source: StreamSource) throws -> ClearKeyMaterial {
        guard let raw = source.drmKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            throw ClearKeyError.missingKey
        }

        let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw ClearKeyError.invalidFormat
        }

        guard let keyID = Self.decodeHex(String(parts[0])), keyID.count == 16 else {
            throw ClearKeyError.invalidKeyID
        }
        guard let key = Self.decodeHex(String(parts[1])), key.count == 16 else {
            throw ClearKeyError.invalidKey
        }

        return ClearKeyMaterial(keyID: keyID, key: key)
    }

    private static func decodeHex(_ value: String) -> Data? {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("0x") {
            normalized.removeFirst(2)
        }
        normalized = normalized.replacingOccurrences(of: "-", with: "")

        guard normalized.count.isMultiple(of: 2), !normalized.isEmpty else {
            return nil
        }

        var data = Data(capacity: normalized.count / 2)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<next], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        return data
    }
}
