import CMAFKit
import CommonCrypto
import Foundation

enum CENCSampleDecryptorError: Error, Equatable {
    case unsupportedScheme
    case invalidKeyLength
    case missingEncryptionMetadata
    case invalidIVLength
    case malformedSubsamples
    case cryptoFailure(Int32)
}

struct CENCSampleDecryptor {
    func decrypt(
        sample: CMAFParsedSample,
        track: CENCTrackInfo,
        material: ClearKeyMaterial
    ) throws -> Data {
        guard let encryption = sample.encryption else {
            throw CENCSampleDecryptorError.missingEncryptionMetadata
        }
        return try decrypt(
            bytes: sample.bytes,
            encryption: encryption,
            track: track,
            material: material
        )
    }

    func decrypt(
        bytes: Data,
        encryption: CMAFSampleInput.EncryptionMetadata,
        track: CENCTrackInfo,
        material: ClearKeyMaterial
    ) throws -> Data {
        guard track.scheme == .cenc else {
            throw CENCSampleDecryptorError.unsupportedScheme
        }
        guard material.key.count == kCCKeySizeAES128 else {
            throw CENCSampleDecryptorError.invalidKeyLength
        }
        try CMAFCENCInspector().validate(material: material, for: track)

        let sampleIV: Data
        if encryption.initializationVector.isEmpty {
            guard let constantIV = track.constantIV else {
                throw CENCSampleDecryptorError.invalidIVLength
            }
            sampleIV = constantIV
        } else {
            sampleIV = encryption.initializationVector
        }
        let counter = try makeCounterBlock(from: sampleIV)

        return try withCTRCryptor(key: material.key, counter: counter) { cryptor in
            guard let subsamples = encryption.subsamples else {
                return try update(bytes, using: cryptor)
            }

            if subsamples.isEmpty {
                return bytes
            }

            var output = Data()
            output.reserveCapacity(bytes.count)
            var offset = 0

            for partition in subsamples {
                let clearCount = Int(partition.bytesOfClearData)
                let protectedCount = Int(partition.bytesOfProtectedData)
                guard clearCount >= 0,
                      protectedCount >= 0,
                      offset <= bytes.count,
                      clearCount <= bytes.count - offset else {
                    throw CENCSampleDecryptorError.malformedSubsamples
                }

                if clearCount > 0 {
                    output.append(bytes[offset..<(offset + clearCount)])
                    offset += clearCount
                }

                guard protectedCount <= bytes.count - offset else {
                    throw CENCSampleDecryptorError.malformedSubsamples
                }
                if protectedCount > 0 {
                    let protected = Data(bytes[offset..<(offset + protectedCount)])
                    output.append(try update(protected, using: cryptor))
                    offset += protectedCount
                }
            }

            guard offset == bytes.count else {
                throw CENCSampleDecryptorError.malformedSubsamples
            }
            return output
        }
    }

    private func makeCounterBlock(from iv: Data) throws -> Data {
        switch iv.count {
        case 8:
            var counter = iv
            counter.append(Data(repeating: 0, count: 8))
            return counter
        case 16:
            return iv
        default:
            throw CENCSampleDecryptorError.invalidIVLength
        }
    }

    private func withCTRCryptor<T>(
        key: Data,
        counter: Data,
        body: (CCCryptorRef) throws -> T
    ) throws -> T {
        var cryptor: CCCryptorRef?
        let status: CCCryptorStatus = key.withUnsafeBytes { keyBytes in
            counter.withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(
                    CCOperation(kCCDecrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivBytes.baseAddress,
                    keyBytes.baseAddress,
                    key.count,
                    nil,
                    0,
                    0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptor
                )
            }
        }

        guard status == kCCSuccess, let cryptor else {
            throw CENCSampleDecryptorError.cryptoFailure(status)
        }
        defer { CCCryptorRelease(cryptor) }
        return try body(cryptor)
    }

    private func update(_ input: Data, using cryptor: CCCryptorRef) throws -> Data {
        guard !input.isEmpty else { return Data() }

        var output = Data(count: input.count)
        var moved = 0
        let status: CCCryptorStatus = input.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                CCCryptorUpdate(
                    cryptor,
                    inputBytes.baseAddress,
                    input.count,
                    outputBytes.baseAddress,
                    output.count,
                    &moved
                )
            }
        }
        guard status == kCCSuccess, moved == input.count else {
            throw CENCSampleDecryptorError.cryptoFailure(status)
        }
        output.count = moved
        return output
    }
}
