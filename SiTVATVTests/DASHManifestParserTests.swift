import XCTest
@testable import SiTVATV

final class DASHManifestParserTests: XCTestCase {
    func testParsesBaseURLInheritanceTemplateTimelineAndDefaultKID() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns:cenc="urn:mpeg:cenc:2013" type="static">
          <BaseURL>cdn/</BaseURL>
          <Period id="p0">
            <BaseURL>period/</BaseURL>
            <AdaptationSet id="v" contentType="video" mimeType="video/mp4" codecs="avc1.640028">
              <BaseURL>video/</BaseURL>
              <ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" value="cenc" cenc:default_KID="00112233-4455-6677-8899-aabbccddeeff"/>
              <SegmentTemplate initialization="init-$RepresentationID$.mp4" media="$RepresentationID$-$Time$.m4s" timescale="1000" startNumber="5" presentationTimeOffset="40">
                <SegmentTimeline>
                  <S t="40" d="2000" r="2"/>
                  <S d="3000"/>
                </SegmentTimeline>
              </SegmentTemplate>
              <Representation id="720p" bandwidth="2500000" width="1280" height="720"/>
              <Representation id="1080p" bandwidth="5000000" width="1920" height="1080">
                <BaseURL>hi/</BaseURL>
                <SegmentTemplate media="hi-$Number$.m4s" duration="2000" startNumber="9"/>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """

        let manifest = try DASHManifestParser().parse(
            data: Data(xml.utf8),
            manifestURL: URL(string: "https://example.com/live/manifest.mpd")!
        )

        XCTAssertEqual(manifest.type, .static)
        XCTAssertEqual(manifest.baseURL.absoluteString, "https://example.com/live/cdn/")
        XCTAssertEqual(manifest.periods.count, 1)

        let adaptation = try XCTUnwrap(manifest.periods.first?.adaptationSets.first)
        XCTAssertEqual(adaptation.baseURL.absoluteString, "https://example.com/live/cdn/period/video/")
        XCTAssertEqual(adaptation.representations.count, 2)

        let first = adaptation.representations[0]
        XCTAssertEqual(first.id, "720p")
        XCTAssertEqual(first.mimeType, "video/mp4")
        XCTAssertEqual(first.codecs, "avc1.640028")
        XCTAssertEqual(first.baseURL.absoluteString, "https://example.com/live/cdn/period/video/")
        XCTAssertEqual(first.defaultKeyID?.uuidString.lowercased(), "00112233-4455-6677-8899-aabbccddeeff")
        XCTAssertEqual(first.segmentTemplate?.timescale, 1000)
        XCTAssertEqual(first.segmentTemplate?.startNumber, 5)
        XCTAssertEqual(first.segmentTemplate?.presentationTimeOffset, 40)
        XCTAssertEqual(first.segmentTemplate?.timeline, [
            DASHSegmentTimelineEntry(startTime: 40, duration: 2000, repeatCount: 2),
            DASHSegmentTimelineEntry(startTime: nil, duration: 3000, repeatCount: 0)
        ])

        let second = adaptation.representations[1]
        XCTAssertEqual(second.baseURL.absoluteString, "https://example.com/live/cdn/period/video/hi/")
        XCTAssertEqual(second.segmentTemplate?.initialization, "init-$RepresentationID$.mp4")
        XCTAssertEqual(second.segmentTemplate?.media, "hi-$Number$.m4s")
        XCTAssertEqual(second.segmentTemplate?.timescale, 1000)
        XCTAssertEqual(second.segmentTemplate?.duration, 2000)
        XCTAssertEqual(second.segmentTemplate?.startNumber, 9)
        XCTAssertEqual(second.segmentTemplate?.presentationTimeOffset, 40)
        XCTAssertEqual(second.segmentTemplate?.timeline.count, 2)
    }

    func testParsesDynamicClockMetadataAndCompactKID() throws {
        let xml = """
        <MPD xmlns:cenc="urn:mpeg:cenc:2013"
             type="dynamic"
             minimumUpdatePeriod="PT6.5S"
             availabilityStartTime="2026-10-16T08:00:00Z"
             publishTime="2026-10-16T08:01:00.500Z"
             timeShiftBufferDepth="PT30S"
             suggestedPresentationDelay="PT4S">
          <Period start="PT10S">
            <AdaptationSet contentType="audio" mimeType="audio/mp4">
              <ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" cenc:default_KID="00112233445566778899aabbccddeeff"/>
              <Representation id="audio" bandwidth="128000">
                <SegmentTemplate initialization="init.mp4" media="$Number$.m4s" timescale="48000" duration="96000" startNumber="1"/>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """

        let manifest = try DASHManifestParser().parse(
            data: Data(xml.utf8),
            manifestURL: URL(string: "https://example.com/manifest.mpd")!
        )

        XCTAssertEqual(manifest.type, .dynamic)
        let minimumUpdatePeriod = try XCTUnwrap(manifest.minimumUpdatePeriod)
        XCTAssertEqual(minimumUpdatePeriod, 6.5, accuracy: 0.0001)
        XCTAssertEqual(manifest.timeShiftBufferDepth, 30)
        XCTAssertEqual(manifest.suggestedPresentationDelay, 4)
        XCTAssertEqual(manifest.periods.first?.start, 10)

        let availabilityStartTime = try XCTUnwrap(manifest.availabilityStartTime)
        let publishTime = try XCTUnwrap(manifest.publishTime)
        XCTAssertEqual(publishTime.timeIntervalSince(availabilityStartTime), 60.5, accuracy: 0.001)

        let representation = try XCTUnwrap(manifest.periods.first?.adaptationSets.first?.representations.first)
        XCTAssertEqual(representation.defaultKeyID?.uuidString.lowercased(), "00112233-4455-6677-8899-aabbccddeeff")
        XCTAssertEqual(representation.segmentTemplate?.duration, 96000)
    }

    func testRejectsTimelineEntryWithoutDuration() {
        let xml = """
        <MPD><Period><AdaptationSet><SegmentTemplate><SegmentTimeline><S t="0"/></SegmentTimeline></SegmentTemplate><Representation id="v"/></AdaptationSet></Period></MPD>
        """

        XCTAssertThrowsError(
            try DASHManifestParser().parse(
                data: Data(xml.utf8),
                manifestURL: URL(string: "https://example.com/manifest.mpd")!
            )
        ) { error in
            XCTAssertEqual(error as? DASHManifestParserError, .invalidTimelineEntry)
        }
    }
}
