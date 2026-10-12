import CMAFKit
import XCTest
@testable import SiTVATV

final class CENCInspectorTests: XCTestCase {
    func testExtractsProtectedTrackMetadata() throws {
        let kid = Data((0..<16).map(UInt8.init))
        let encryption = CMAFEncryptionParameters(
            scheme: .cenc,
            defaultKID: KeyIdentifier(rawBytes: kid),
            defaultPerSampleIVSize: .eight,
            defaultCryptByteBlock: 0,
            defaultSkipByteBlock: 0
        )
        let track = makeTrack(id: 7, kind: .video, encryption: encryption)

        let inspection = CMAFCENCInspector().inspect(tracks: [track])

        XCTAssertTrue(inspection.isProtected)
        let info = try XCTUnwrap(inspection.tracks.first)
        XCTAssertEqual(info.trackID, 7)
        XCTAssertEqual(info.kind, .video)
        XCTAssertEqual(info.scheme, .cenc)
        XCTAssertEqual(info.keyID, kid)
        XCTAssertEqual(info.perSampleIVSize, 8)
        XCTAssertNil(info.constantIV)
        XCTAssertEqual(info.cryptByteBlock, 0)
        XCTAssertEqual(info.skipByteBlock, 0)
    }

    func testClearTracksAreNotReportedAsProtected() {
        let clearTrack = makeTrack(id: 1, kind: .audio, encryption: nil)
        let inspection = CMAFCENCInspector().inspect(tracks: [clearTrack])

        XCTAssertFalse(inspection.isProtected)
        XCTAssertTrue(inspection.tracks.isEmpty)
    }

    func testValidatesPlaylistKeyIDAgainstInitMetadata() throws {
        let kid = Data(repeating: 0x11, count: 16)
        let encryption = CMAFEncryptionParameters(
            scheme: .cenc,
            defaultKID: KeyIdentifier(rawBytes: kid),
            defaultPerSampleIVSize: .eight
        )
        let info = try XCTUnwrap(
            CMAFCENCInspector()
                .inspect(tracks: [makeTrack(id: 1, kind: .video, encryption: encryption)])
                .tracks.first
        )
        let material = ClearKeyMaterial(
            keyID: kid,
            key: Data(repeating: 0x22, count: 16)
        )

        XCTAssertNoThrow(try CMAFCENCInspector().validate(material: material, for: info))
    }

    func testRejectsPlaylistKeyIDMismatch() throws {
        let encryption = CMAFEncryptionParameters(
            scheme: .cenc,
            defaultKID: KeyIdentifier(rawBytes: Data(repeating: 0x11, count: 16)),
            defaultPerSampleIVSize: .eight
        )
        let info = try XCTUnwrap(
            CMAFCENCInspector()
                .inspect(tracks: [makeTrack(id: 1, kind: .video, encryption: encryption)])
                .tracks.first
        )
        let material = ClearKeyMaterial(
            keyID: Data(repeating: 0x33, count: 16),
            key: Data(repeating: 0x44, count: 16)
        )

        XCTAssertThrowsError(
            try CMAFCENCInspector().validate(material: material, for: info)
        ) { error in
            XCTAssertEqual(error as? CENCInspectorError, .keyIDMismatch)
        }
    }

    private func makeTrack(
        id: UInt32,
        kind: CMAFTrackKind,
        encryption: CMAFEncryptionParameters?
    ) -> CMAFTrackConfiguration {
        CMAFTrackConfiguration(
            trackID: id,
            kind: kind,
            profile: .dash,
            timescale: 1_000,
            language: "und",
            encryptionParameters: encryption
        )
    }
}
