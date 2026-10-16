import XCTest
@testable import SiTVATV

final class DASHByteRangeResourceLoaderTests: XCTestCase {
    func testRangeRequestUsesHTTPRangeAndAcceptsExact206Body() async throws {
        let url = URL(string: "https://example.com/video.mp4")!
        let body = Data([10, 11, 12, 13])
        let client = ByteRangeHTTPClient(
            data: body,
            statusCode: 206,
            headerFields: ["Content-Range": "bytes 100-103/1000"]
        )
        let loader = DASHResourceLoader(client: client)

        let data = try await loader.loadData(
            from: url,
            headers: ["Referer": "https://example.com/"],
            byteRange: DASHByteRange(start: 100, end: 103)
        )

        XCTAssertEqual(data, body)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=100-103")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://example.com/")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testCoalesced206RangeSlicesRequestedOffsets() async throws {
        let url = URL(string: "https://example.com/video.mp4")!
        let body = Data([8, 9, 10, 11, 12, 13, 14, 15])
        let client = ByteRangeHTTPClient(
            data: body,
            statusCode: 206,
            headerFields: ["Content-Range": "bytes 98-105/1000"]
        )
        let loader = DASHResourceLoader(client: client)

        let data = try await loader.loadData(
            from: url,
            headers: [:],
            byteRange: DASHByteRange(start: 100, end: 103)
        )

        XCTAssertEqual(data, Data([10, 11, 12, 13]))
    }

    func testRejects206FromWrongOffset() async {
        let url = URL(string: "https://example.com/video.mp4")!
        let client = ByteRangeHTTPClient(
            data: Data([1, 2, 3, 4]),
            statusCode: 206,
            headerFields: ["Content-Range": "bytes 200-203/1000"]
        )
        let loader = DASHResourceLoader(client: client)

        do {
            _ = try await loader.loadData(
                from: url,
                headers: [:],
                byteRange: DASHByteRange(start: 100, end: 103)
            )
            XCTFail("Expected mismatched content range")
        } catch {
            XCTAssertEqual(
                error as? DASHResourceLoaderError,
                .mismatchedContentRange(
                    expectedStart: 100,
                    expectedEnd: 103,
                    actualStart: 200,
                    actualEnd: 203
                )
            )
        }
    }

    func testServerIgnoringRangeSlicesFull200Response() async throws {
        let url = URL(string: "https://example.com/video.mp4")!
        let body = Data((0..<16).map(UInt8.init))
        let client = ByteRangeHTTPClient(data: body, statusCode: 200)
        let loader = DASHResourceLoader(client: client)

        let data = try await loader.loadData(
            from: url,
            headers: [:],
            byteRange: DASHByteRange(start: 4, end: 7)
        )

        XCTAssertEqual(data, Data([4, 5, 6, 7]))
    }

    func testRejectsShortRangeBody() async {
        let url = URL(string: "https://example.com/video.mp4")!
        let client = ByteRangeHTTPClient(data: Data([1, 2]), statusCode: 206)
        let loader = DASHResourceLoader(client: client)

        do {
            _ = try await loader.loadData(
                from: url,
                headers: [:],
                byteRange: DASHByteRange(start: 100, end: 103)
            )
            XCTFail("Expected incomplete range error")
        } catch {
            XCTAssertEqual(
                error as? DASHResourceLoaderError,
                .incompleteByteRange(expected: 4, available: 2)
            )
        }
    }
}

private final class ByteRangeHTTPClient: DASHHTTPClient {
    let data: Data
    let statusCode: Int
    let headerFields: [String: String]
    private(set) var requests: [URLRequest] = []

    init(
        data: Data,
        statusCode: Int,
        headerFields: [String: String] = [:]
    ) {
        self.data = data
        self.statusCode = statusCode
        self.headerFields = headerFields
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
        return (data, response)
    }
}
