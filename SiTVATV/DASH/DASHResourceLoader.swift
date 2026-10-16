import Foundation

protocol DASHHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionDASHHTTPClient: DASHHTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DASHResourceLoaderError.nonHTTPResponse
        }
        return (data, httpResponse)
    }
}

enum DASHResourceLoaderError: Error, Equatable {
    case nonHTTPResponse
    case httpStatus(Int)
    case invalidByteRange
    case incompleteByteRange(expected: Int, available: Int)
    case invalidContentRange(String)
    case mismatchedContentRange(
        expectedStart: UInt64,
        expectedEnd: UInt64,
        actualStart: UInt64,
        actualEnd: UInt64
    )
}

protocol DASHResourceLoading {
    func loadManifest(
        from url: URL,
        headers: [String: String]
    ) async throws -> DASHManifest

    func loadData(
        from url: URL,
        headers: [String: String]
    ) async throws -> Data

    func loadData(
        from url: URL,
        headers: [String: String],
        byteRange: DASHByteRange?
    ) async throws -> Data
}

extension DASHResourceLoading {
    func loadData(
        from url: URL,
        headers: [String: String],
        byteRange: DASHByteRange?
    ) async throws -> Data {
        let data = try await loadData(from: url, headers: headers)
        guard let byteRange else { return data }
        return try DASHResourceLoader.slice(data, for: byteRange)
    }
}

struct DASHResourceLoader: DASHResourceLoading {
    private let client: any DASHHTTPClient
    private let timeout: TimeInterval

    init(
        client: any DASHHTTPClient = URLSessionDASHHTTPClient(),
        timeout: TimeInterval = 15
    ) {
        self.client = client
        self.timeout = timeout
    }

    func loadManifest(
        from url: URL,
        headers: [String: String] = [:]
    ) async throws -> DASHManifest {
        let data = try await loadData(from: url, headers: headers)
        return try DASHManifestParser().parse(data: data, manifestURL: url)
    }

    func loadData(
        from url: URL,
        headers: [String: String] = [:]
    ) async throws -> Data {
        try await loadData(from: url, headers: headers, byteRange: nil)
    }

    func loadData(
        from url: URL,
        headers: [String: String] = [:],
        byteRange: DASHByteRange?
    ) async throws -> Data {
        let request = makeRequest(url: url, headers: headers, byteRange: byteRange)
        let (data, response) = try await client.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw DASHResourceLoaderError.httpStatus(response.statusCode)
        }
        guard let byteRange else { return data }

        let expected = try Self.expectedLength(for: byteRange)
        if response.statusCode == 206 {
            if let rawContentRange = response.value(forHTTPHeaderField: "Content-Range") {
                let actual = try Self.parseContentRange(rawContentRange)
                guard actual.start <= byteRange.start,
                      actual.end >= byteRange.end else {
                    throw DASHResourceLoaderError.mismatchedContentRange(
                        expectedStart: byteRange.start,
                        expectedEnd: byteRange.end,
                        actualStart: actual.start,
                        actualEnd: actual.end
                    )
                }

                let actualLength64 = actual.end - actual.start + 1
                guard actualLength64 <= UInt64(Int.max) else {
                    throw DASHResourceLoaderError.invalidByteRange
                }
                let actualLength = Int(actualLength64)
                guard data.count >= actualLength else {
                    throw DASHResourceLoaderError.incompleteByteRange(
                        expected: actualLength,
                        available: data.count
                    )
                }

                let relativeStart64 = byteRange.start - actual.start
                let relativeEnd64 = byteRange.end - actual.start
                guard relativeStart64 <= UInt64(Int.max),
                      relativeEnd64 <= UInt64(Int.max) else {
                    throw DASHResourceLoaderError.invalidByteRange
                }
                let relativeStart = Int(relativeStart64)
                let relativeEnd = Int(relativeEnd64)
                guard relativeEnd < data.count else {
                    throw DASHResourceLoaderError.incompleteByteRange(
                        expected: expected,
                        available: max(data.count - relativeStart, 0)
                    )
                }
                return data.subdata(in: relativeStart..<(relativeEnd + 1))
            }

            // A few compliant-enough CDNs omit Content-Range even for a 206.
            // Keep compatibility only when the body itself exactly matches the
            // requested length; a larger ambiguous body must not be guessed.
            guard data.count == expected else {
                throw DASHResourceLoaderError.incompleteByteRange(
                    expected: expected,
                    available: data.count
                )
            }
            return data
        }

        // Some CDNs ignore Range and answer 200 with the full object. Slice the
        // requested range locally; never feed a full MP4 to a sub-range parser.
        if data.count == expected {
            return data
        }
        return try Self.slice(data, for: byteRange)
    }

    private func makeRequest(
        url: URL,
        headers: [String: String],
        byteRange: DASHByteRange?
    ) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "GET"
        request.setValue("SiTV/0.1 tvOS", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        if let byteRange {
            request.setValue(byteRange.httpHeaderValue, forHTTPHeaderField: "Range")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    static func slice(_ data: Data, for range: DASHByteRange) throws -> Data {
        guard range.start <= UInt64(Int.max), range.end <= UInt64(Int.max) else {
            throw DASHResourceLoaderError.invalidByteRange
        }
        let start = Int(range.start)
        let end = Int(range.end)
        let expected = try expectedLength(for: range)
        guard start >= 0, end >= start, end < data.count else {
            throw DASHResourceLoaderError.incompleteByteRange(
                expected: expected,
                available: max(data.count - min(start, data.count), 0)
            )
        }
        return data.subdata(in: start..<(end + 1))
    }

    private static func parseContentRange(_ value: String) throws -> DASHByteRange {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bytes ") else {
            throw DASHResourceLoaderError.invalidContentRange(value)
        }
        let payload = trimmed.dropFirst(6)
        let rangePart = payload.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        guard let range = DASHByteRange.parse(rangePart) else {
            throw DASHResourceLoaderError.invalidContentRange(value)
        }
        return range
    }

    private static func expectedLength(for range: DASHByteRange) throws -> Int {
        guard range.length > 0, range.length <= UInt64(Int.max) else {
            throw DASHResourceLoaderError.invalidByteRange
        }
        return Int(range.length)
    }
}
