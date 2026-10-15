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
        let request = makeRequest(url: url, headers: headers)
        let (data, response) = try await client.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw DASHResourceLoaderError.httpStatus(response.statusCode)
        }
        return data
    }

    private func makeRequest(url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "GET"
        request.setValue("SiTV/0.1 tvOS", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}
