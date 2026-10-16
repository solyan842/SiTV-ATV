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
            guard data.count >= expected else {
                throw DASHResourceLoaderError.incompleteByteRange(
                    expected: expected,
                    available: data.count
                )
            }
            return data.count == expected ? data : Data(data.prefix(expected))
        }

        // Some CDNs legally ignore Range and answer 200 with the full object.
        // Slice the requested range locally rather than feeding the whole MP4
        // into a parser that expects an init/index/media sub-range.
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

    private static func expectedLength(for range: DASHByteRange) throws -> Int {
        guard range.length > 0, range.length <= UInt64(Int.max) else {
            throw DASHResourceLoaderError.invalidByteRange
        }
        return Int(range.length)
    }
}
