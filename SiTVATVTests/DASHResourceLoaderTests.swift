import XCTest
@testable import SiTVATV

final class DASHResourceLoaderTests: XCTestCase {
    func testLoadManifestAppliesHeadersAndParsesResponse() async throws {
        let url = URL(string: "https://example.com/live/manifest.mpd")!
        let xml = """
        <MPD type="static">
          <Period><AdaptationSet><Representation id="v"/></AdaptationSet></Period>
        </MPD>
        """
        let client = MockDASHHTTPClient(
            data: Data(xml.utf8),
            statusCode: 200
        )
        let loader = DASHResourceLoader(client: client, timeout: 9)

        let manifest = try await loader.loadManifest(
            from: url,
            headers: ["Referer": "https://example.com/", "X-Test": "yes"]
        )

        XCTAssertEqual(manifest.type, .static)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 9, accuracy: 0.001)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://example.com/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "yes")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "SiTV/0.1 tvOS")
    }

    func testExplicitUserAgentOverridesDefault() async throws {
        let url = URL(string: "https://example.com/segment.m4s")!
        let client = MockDASHHTTPClient(data: Data([1, 2, 3]), statusCode: 200)
        let loader = DASHResourceLoader(client: client)

        _ = try await loader.loadData(
            from: url,
            headers: ["User-Agent": "Custom-UA"]
        )

        XCTAssertEqual(
            client.requests.first?.value(forHTTPHeaderField: "User-Agent"),
            "Custom-UA"
        )
    }

    func testRejectsNonSuccessHTTPStatus() async {
        let url = URL(string: "https://example.com/missing.m4s")!
        let client = MockDASHHTTPClient(data: Data(), statusCode: 403)
        let loader = DASHResourceLoader(client: client)

        do {
            _ = try await loader.loadData(from: url)
            XCTFail("Expected HTTP status failure")
        } catch {
            XCTAssertEqual(error as? DASHResourceLoaderError, .httpStatus(403))
        }
    }
}

private final class MockDASHHTTPClient: DASHHTTPClient {
    let data: Data
    let statusCode: Int
    private(set) var requests: [URLRequest] = []

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (data, response)
    }
}
