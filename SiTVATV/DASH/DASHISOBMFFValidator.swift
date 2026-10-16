import Foundation

enum DASHISOBMFFValidationError: Error, Equatable, Sendable {
    case invalidInitializationSegment(bytes: Int)
    case invalidMediaSegment(bytes: Int)
}

struct DASHISOBMFFValidator {
    func validateInitializationSegment(_ data: Data) throws {
        guard let types = topLevelBoxTypes(in: data),
              types.contains("moov") else {
            throw DASHISOBMFFValidationError.invalidInitializationSegment(bytes: data.count)
        }
    }

    func validateMediaSegment(_ data: Data) throws {
        guard let types = topLevelBoxTypes(in: data),
              types.contains("moof"),
              types.contains("mdat") else {
            throw DASHISOBMFFValidationError.invalidMediaSegment(bytes: data.count)
        }
    }

    private func topLevelBoxTypes(in data: Data) -> Set<String>? {
        guard data.count >= 8 else { return nil }

        var offset = 0
        var types = Set<String>()

        while offset < data.count {
            guard data.count - offset >= 8,
                  let size32 = readUInt32(data, at: offset),
                  let type = readType(data, at: offset + 4) else {
                return nil
            }

            var headerSize = 8
            let boxSize: UInt64
            switch size32 {
            case 0:
                boxSize = UInt64(data.count - offset)
            case 1:
                guard data.count - offset >= 16,
                      let size64 = readUInt64(data, at: offset + 8) else {
                    return nil
                }
                headerSize = 16
                boxSize = size64
            default:
                boxSize = UInt64(size32)
            }

            guard boxSize >= UInt64(headerSize),
                  boxSize <= UInt64(data.count - offset),
                  boxSize <= UInt64(Int.max) else {
                return nil
            }

            types.insert(type)
            offset += Int(boxSize)
        }

        return offset == data.count ? types : nil
    }

    private func readType(_ data: Data, at offset: Int) -> String? {
        guard offset >= 0, data.count - offset >= 4 else { return nil }
        return String(
            data: data.subdata(in: offset..<(offset + 4)),
            encoding: .ascii
        )
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, data.count - offset >= 4 else { return nil }
        return data[offset..<(offset + 4)].reduce(UInt32(0)) { value, byte in
            (value << 8) | UInt32(byte)
        }
    }

    private func readUInt64(_ data: Data, at offset: Int) -> UInt64? {
        guard offset >= 0, data.count - offset >= 8 else { return nil }
        return data[offset..<(offset + 8)].reduce(UInt64(0)) { value, byte in
            (value << 8) | UInt64(byte)
        }
    }
}
