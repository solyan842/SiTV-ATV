import CMAFKit
import XCTest
@testable import SiTVATV

final class CENCSampleDecryptorTests: XCTestCase {
    func testDecryptsNISTAESCTRVector() throws {
        let key = try XCTUnwrap(Data(hex: "2b7e151628aed2a6abf7158809cf4f3c"))
        let iv = try XCTUnwrap(Data(hex: "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"))
        let ciphertext = try XCTUnwrap(Data(hex:
            "874d6191b620e3261bef6864990db6ce" +
            "9806f66b7970fdff8617187bb9fffdff"
        ))
        let plaintext = try XCTUnwrap(Data(hex:
            "6bc1bee22e409f96e93d7e117393172a" +
            "ae2d8a571e03ac9c9eb76fac45af8e51"
        ))
        let kid = Data(repeating: 0x11, count: 16)

        let decrypted = try CENCSampleDecryptor().decrypt(
            bytes: ciphertext,
            encryption: .init(initializationVector: iv),
            track: makeTrackInfo(keyID: kid),
            material: ClearKeyMaterial(keyID: kid, key: key)
        )

        XCTAssertEqual(decrypted, plaintext)
    }

    func testEightByteCENCIVIsZeroExtendedToCounterBlock() throws {
        let key = try XCTUnwrap(Data(hex: "2b7e151628aed2a6abf7158809cf4f3c"))
        let iv = try XCTUnwrap(Data(hex: "f0f1f2f3f4f5f6f7"))
        let ciphertext = try XCTUnwrap(Data(hex: "67ee05547499f8bcf0c38324e8605c28"))
        let plaintext = try XCTUnwrap(Data(hex: "6bc1bee22e409f96e93d7e117393172a"))
        let kid = Data(repeating: 0x22, count: 16)

        let decrypted = try CENCSampleDecryptor().decrypt(
            bytes: ciphertext,
            encryption: .init(initializationVector: iv),
            track: makeTrackInfo(keyID: kid, ivSize: 8),
            material: ClearKeyMaterial(keyID: kid, key: key)
        )

        XCTAssertEqual(decrypted, plaintext)
    }

    func testSubsampleCTRStateContinuesAcrossClearRanges() throws {
        let key = try XCTUnwrap(Data(hex: "2b7e151628aed2a6abf7158809cf4f3c"))
        let iv = try XCTUnwrap(Data(hex: "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"))
        let cipher1 = try XCTUnwrap(Data(hex: "874d6191b620e3261bef6864990db6ce"))
        let cipher2 = try XCTUnwrap(Data(hex: "9806f66b7970fdff8617187bb9fffdff"))
        let plain1 = try XCTUnwrap(Data(hex: "6bc1bee22e409f96e93d7e117393172a"))
        let plain2 = try XCTUnwrap(Data(hex: "ae2d8a571e03ac9c9eb76fac45af8e51"))
        let kid = Data(repeating: 0x33, count: 16)

        var encryptedSample = Data([0xAA, 0xBB])
        encryptedSample.append(cipher1)
        encryptedSample.append(0xCC)
        encryptedSample.append(cipher2)

        let encryption = CMAFSampleInput.EncryptionMetadata(
            initializationVector: iv,
            subsamples: [
                .init(bytesOfClearData: 2, bytesOfProtectedData: 16),
                .init(bytesOfClearData: 1, bytesOfProtectedData: 16)
            ]
        )

        let decrypted = try CENCSampleDecryptor().decrypt(
            bytes: encryptedSample,
            encryption: encryption,
            track: makeTrackInfo(keyID: kid),
            material: ClearKeyMaterial(keyID: kid, key: key)
        )

        var expected = Data([0xAA, 0xBB])
        expected.append(plain1)
        expected.append(0xCC)
        expected.append(plain2)
        XCTAssertEqual(decrypted, expected)
    }

    func testRejectsUnsupportedSchemeAndMalformedSubsamples() throws {
        let kid = Data(repeating: 0x44, count: 16)
        let key = Data(repeating: 0x55, count: 16)
        let encryption = CMAFSampleInput.EncryptionMetadata(
            initializationVector: Data(repeating: 0, count: 16)
        )

        XCTAssertThrowsError(
            try CENCSampleDecryptor().decrypt(
                bytes: Data([1, 2, 3]),
                encryption: encryption,
                track: makeTrackInfo(keyID: kid, scheme: .cbcs),
                material: ClearKeyMaterial(keyID: kid, key: key)
            )
        ) { error in
            XCTAssertEqual(error as? CENCSampleDecryptorError, .unsupportedScheme)
        }

        let malformed = CMAFSampleInput.EncryptionMetadata(
            initializationVector: Data(repeating: 0, count: 16),
            subsamples: [.init(bytesOfClearData: 4, bytesOfProtectedData: 10)]
        )
        XCTAssertThrowsError(
            try CENCSampleDecryptor().decrypt(
                bytes: Data(repeating: 0, count: 8),
                encryption: malformed,
                track: makeTrackInfo(keyID: kid),
                material: ClearKeyMaterial(keyID: kid, key: key)
            )
        ) { error in
            XCTAssertEqual(error as? CENCSampleDecryptorError, .malformedSubsamples)
        }
    }

    private func makeTrackInfo(
        keyID: Data,
        scheme: CommonEncryptionScheme = .cenc,
        ivSize: UInt8 = 16
    ) -> CENCTrackInfo {
        CENCTrackInfo(
            trackID: 1,
            kind: .video,
            scheme: scheme,
            keyID: keyID,
            perSampleIVSize: ivSize,
            constantIV: nil,
            cryptByteBlock: 0,
            skipByteBlock: 0
        )
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
