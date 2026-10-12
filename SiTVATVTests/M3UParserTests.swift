import XCTest
@testable import SiTVATV

final class M3UParserTests: XCTestCase {
    func testParsesClearKeyHeadersAndMultipleSources() throws {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 tvg-id="hbo" tvg-name="HBO" group-title="Quốc tế" tvg-logo="https://img.example/hbo.png",HBO
        #KODIPROP:inputstream.adaptive.manifest_type=mpd
        #KODIPROP:inputstream.adaptive.license_type=org.w3.clearkey
        #KODIPROP:inputstream.adaptive.license_key=00112233445566778899aabbccddeeff:ffeeddccbbaa99887766554433221100
        #EXTVLCOPT:http-referrer=https://example.com/
        #EXTVLCOPT:http-user-agent=SiTV-Test
        https://cdn.example/hbo.mpd|X-Test=hello%20world
        https://backup.example/hbo.mpd
        """

        let channels = M3UParser().parse(playlist)
        XCTAssertEqual(channels.count, 1)

        let channel = try XCTUnwrap(channels.first)
        XCTAssertEqual(channel.id, "hbo")
        XCTAssertEqual(channel.name, "HBO")
        XCTAssertEqual(channel.group, "Quốc tế")
        XCTAssertEqual(channel.logoURL, "https://img.example/hbo.png")
        XCTAssertEqual(channel.sources.count, 2)

        let source = try XCTUnwrap(channel.sources.first)
        XCTAssertEqual(source.manifestType, "mpd")
        XCTAssertEqual(source.drmType, "org.w3.clearkey")
        XCTAssertEqual(source.drmKey, "00112233445566778899aabbccddeeff:ffeeddccbbaa99887766554433221100")
        XCTAssertEqual(source.headers["Referer"], "https://example.com/")
        XCTAssertEqual(source.headers["User-Agent"], "SiTV-Test")
        XCTAssertEqual(source.headers["X-Test"], "hello world")
    }

    func testParsesLegacyLicenseURLAndHeaders() throws {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 tvg-name="Test",Test
        #KODIPROP:inputstream.adaptive.license_url=https://license.example/path|Authorization=Bearer%20abc
        https://cdn.example/live.mpd
        """

        let source = try XCTUnwrap(M3UParser().parse(playlist).first?.sources.first)
        XCTAssertEqual(source.licenseURI, "https://license.example/path")
        XCTAssertEqual(source.licenseHeaders["Authorization"], "Bearer abc")
    }

    func testRejectsNonM3UText() {
        XCTAssertTrue(M3UParser().parse("https://example.com/live.m3u8").isEmpty)
    }
}
