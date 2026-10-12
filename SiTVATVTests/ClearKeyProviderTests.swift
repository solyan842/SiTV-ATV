import XCTest
@testable import SiTVATV

final class ClearKeyProviderTests: XCTestCase {
    func testParsesHexKidAndKey() throws {
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd",
            drmType: "clearkey",
            drmKey: "00112233445566778899aabbccddeeff:ffeeddccbbaa99887766554433221100"
        )

        let material = try PlaylistClearKeyProvider().material(for: source)

        XCTAssertEqual(material.keyID.count, 16)
        XCTAssertEqual(material.key.count, 16)
        XCTAssertEqual(material.keyID.map { String(format: "%02x", $0) }.joined(), "00112233445566778899aabbccddeeff")
        XCTAssertEqual(material.key.map { String(format: "%02x", $0) }.joined(), "ffeeddccbbaa99887766554433221100")
    }

    func testAcceptsUUIDStyleKid() throws {
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd",
            drmType: "clearkey",
            drmKey: "00112233-4455-6677-8899-aabbccddeeff:ffeeddccbbaa99887766554433221100"
        )

        XCTAssertNoThrow(try PlaylistClearKeyProvider().material(for: source))
    }

    func testRejectsMissingKey() {
        let source = StreamSource(url: "https://example.com/live.mpd", manifestType: "mpd", drmType: "clearkey")
        XCTAssertThrowsError(try PlaylistClearKeyProvider().material(for: source)) { error in
            XCTAssertEqual(error as? ClearKeyError, .missingKey)
        }
    }

    func testRejectsWrongLength() {
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd",
            drmType: "clearkey",
            drmKey: "0011:ffeeddccbbaa99887766554433221100"
        )

        XCTAssertThrowsError(try PlaylistClearKeyProvider().material(for: source)) { error in
            XCTAssertEqual(error as? ClearKeyError, .invalidKeyID)
        }
    }
}
