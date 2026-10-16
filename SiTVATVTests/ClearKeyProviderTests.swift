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

    func testParsesMultipleHexPairsWithoutDroppingAudioKey() throws {
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd",
            drmType: "clearkey",
            drmKey: "00112233445566778899aabbccddeeff:ffeeddccbbaa99887766554433221100,102132435465768798a9bacbdcedfe0f:00112233445566778899aabbccddeeff"
        )

        let materials = try PlaylistClearKeyProvider().materials(for: source)

        XCTAssertEqual(materials.count, 2)
        XCTAssertEqual(materials[0].keyID.map { String(format: "%02x", $0) }.joined(), "00112233445566778899aabbccddeeff")
        XCTAssertEqual(materials[1].keyID.map { String(format: "%02x", $0) }.joined(), "102132435465768798a9bacbdcedfe0f")
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

    func testParsesClearKeyJWKJSON() throws {
        let kid = Data((0..<16).map(UInt8.init))
        let key = Data((16..<32).map(UInt8.init))
        let json = """
        {"keys":[{"kty":"oct","kid":"\(ClearKeyJWKParser.encodeBase64URL(kid))","k":"\(ClearKeyJWKParser.encodeBase64URL(key))"}],"type":"temporary"}
        """
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd",
            drmType: "org.w3.clearkey",
            drmKey: json
        )

        let material = try PlaylistClearKeyProvider().material(for: source)
        XCTAssertEqual(material.keyID, kid)
        XCTAssertEqual(material.key, key)
    }

    func testParsesEveryJWKMaterial() throws {
        let firstKID = Data((0..<16).map(UInt8.init))
        let firstKey = Data((16..<32).map(UInt8.init))
        let secondKID = Data((32..<48).map(UInt8.init))
        let secondKey = Data((48..<64).map(UInt8.init))
        let json = """
        {"keys":[
          {"kty":"oct","kid":"\(ClearKeyJWKParser.encodeBase64URL(firstKID))","k":"\(ClearKeyJWKParser.encodeBase64URL(firstKey))"},
          {"kty":"oct","kid":"\(ClearKeyJWKParser.encodeBase64URL(secondKID))","k":"\(ClearKeyJWKParser.encodeBase64URL(secondKey))"}
        ],"type":"temporary"}
        """
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd",
            drmType: "org.w3.clearkey",
            drmKey: json
        )

        let materials = try PlaylistClearKeyProvider().materials(for: source)

        XCTAssertEqual(materials.map(\.keyID), [firstKID, secondKID])
        XCTAssertEqual(materials.map(\.key), [firstKey, secondKey])
    }

    func testParsesBase64DataURIJWK() throws {
        let kid = Data((0..<16).map(UInt8.init))
        let key = Data((16..<32).map(UInt8.init))
        let json = """
        {"keys":[{"kty":"oct","kid":"\(ClearKeyJWKParser.encodeBase64URL(kid))","k":"\(ClearKeyJWKParser.encodeBase64URL(key))"}]}
        """
        let encoded = Data(json.utf8).base64EncodedString()
        let source = StreamSource(
            url: "https://example.com/live.mpd",
            manifestType: "mpd",
            drmType: "clearkey",
            drmKey: "data:application/json;base64,\(encoded)"
        )

        let material = try PlaylistClearKeyProvider().material(for: source)
        XCTAssertEqual(material.keyID, kid)
        XCTAssertEqual(material.key, key)
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
