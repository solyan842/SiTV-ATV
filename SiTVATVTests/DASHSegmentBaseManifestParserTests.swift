import XCTest
@testable import SiTVATV

final class DASHSegmentBaseManifestParserTests: XCTestCase {
    func testParsesInheritedSegmentBaseAndInitializationRange() throws {
        let xml = """
        <MPD type="static">
          <Period id="p0">
            <AdaptationSet contentType="video" mimeType="video/mp4" codecs="avc1.640028">
              <SegmentBase indexRange="100-199">
                <Initialization range="0-99"/>
              </SegmentBase>
              <Representation id="v1" bandwidth="2500000" width="1280" height="720">
                <BaseURL>video.mp4</BaseURL>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """

        let manifest = try DASHManifestParser().parse(
            data: Data(xml.utf8),
            manifestURL: URL(string: "https://example.com/path/manifest.mpd")!
        )
        let representation = try XCTUnwrap(
            manifest.periods.first?.adaptationSets.first?.representations.first
        )

        XCTAssertEqual(representation.baseURL.absoluteString, "https://example.com/path/video.mp4")
        XCTAssertEqual(representation.segmentBase?.indexRange, DASHByteRange(start: 100, end: 199))
        XCTAssertEqual(representation.segmentBase?.initializationRange, DASHByteRange(start: 0, end: 99))
    }

    func testRepresentationSegmentBaseOverridesAdaptationIndexRange() throws {
        let xml = """
        <MPD type="static">
          <Period>
            <AdaptationSet contentType="audio" mimeType="audio/mp4" codecs="mp4a.40.2">
              <SegmentBase indexRange="100-199"><Initialization range="0-99"/></SegmentBase>
              <Representation id="a1" bandwidth="128000">
                <BaseURL>audio.mp4</BaseURL>
                <SegmentBase indexRange="200-299"/>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """

        let manifest = try DASHManifestParser().parse(
            data: Data(xml.utf8),
            manifestURL: URL(string: "https://example.com/manifest.mpd")!
        )
        let representation = try XCTUnwrap(
            manifest.periods.first?.adaptationSets.first?.representations.first
        )

        XCTAssertEqual(representation.segmentBase?.indexRange, DASHByteRange(start: 200, end: 299))
        XCTAssertEqual(representation.segmentBase?.initializationRange, DASHByteRange(start: 0, end: 99))
    }
}
