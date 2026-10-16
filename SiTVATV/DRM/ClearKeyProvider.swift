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

protocol ClearKeyCollectionProviding: ClearKeyProviding {
    func materials(for source: StreamSource) throws -> [ClearKeyMaterial]
}

struct PlaylistClearKeyProvider: ClearKeyCollectionProviding {
    func material(for source: StreamSource) throws -> ClearKeyMaterial {
        guard let first = try materials(for: source).first else {
            throw ClearKeyError.invalidFormat
        }
        return first
    }

    func materials(for source: StreamSource) throws -> [ClearKeyMaterial] {
        guard let raw = source.drmKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            throw ClearKeyError.missingKey
        }

        if raw.lowercased().hasPrefix("data:application/json;base64,") {
            let encoded = String(raw.dropFirst("data:application/json;base64,".count))
            guard let data = Data(base64Encoded: encoded) else {
                throw ClearKeyError.invalidFormat
            }
            return try ClearKeyJWKParser.materials(from: data)
        }

        if raw.hasPrefix("{") {
            guard let data = raw.data(using: .utf8) else {
                throw ClearKeyError.invalidFormat
            }
            return try ClearKeyJWKParser.materials(from: data)
        }

        let entries = raw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !entries.isEmpty else {
            throw ClearKeyError.invalidFormat
        }

        return try entries.map(Self.parseHexPair)
    }

    private static func parseHexPair(_ raw: String) throws -> ClearKeyMaterial {
        let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw ClearKeyError.invalidFormat
        }

        guard let keyID = decodeHex(String(parts[0])), keyID.count == 16 else {
            throw ClearKeyError.invalidKeyID
        }
        guard let key = decodeHex(String(parts[1])), key.count == 16 else {
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

enum ClearKeyJWKParser {
    static func materials(from data: Data) throws -> [ClearKeyMaterial] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let keys = dictionary["keys"] as? [[String: Any]],
              !keys.isEmpty else {
            throw ClearKeyError.invalidFormat
        }

        let materials = try keys.compactMap { item -> ClearKeyMaterial? in
            guard let kidValue = item["kid"] as? String,
                  let keyValue = item["k"] as? String else {
                return nil
            }
            guard let keyID = decodeBase64URL(kidValue), keyID.count == 16 else {
                throw ClearKeyError.invalidKeyID
            }
            guard let key = decodeBase64URL(keyValue), key.count == 16 else {
                throw ClearKeyError.invalidKey
            }
            return ClearKeyMaterial(keyID: keyID, key: key)
        }

        guard !materials.isEmpty else {
            throw ClearKeyError.invalidFormat
        }
        return materials
    }

    static func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: normalized)
    }
}
