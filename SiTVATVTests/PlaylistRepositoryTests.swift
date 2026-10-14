import XCTest
@testable import SiTVATV

final class PlaylistRepositoryTests: XCTestCase {
    func testFiveSlotsAndActiveSourceFallback() async throws {
        let suite = "SiTVATVTests.PlaylistRepository.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Unable to create isolated UserDefaults")
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let repository = PlaylistRepository(defaults: defaults)

        let initial = await repository.sources()
        XCTAssertEqual(initial.count, 5)
        XCTAssertTrue(initial.allSatisfy { !$0.isConfigured })

        await repository.saveSources([
            PlaylistSource(slot: 1, name: "Primary", url: "https://example.com/one.m3u"),
            PlaylistSource(slot: 3, name: "Backup", url: "https://example.com/two.m3u")
        ])

        let configuredSlots = await repository.configuredSources().map(\.slot)
        let initialActive = await repository.activeSourceIndex()
        XCTAssertEqual(configuredSlots, [1, 3])
        XCTAssertEqual(initialActive, 1)

        await repository.selectSource(slot: 3)
        let selectedActive = await repository.activeSourceIndex()
        let selectedName = await repository.activeSource().name
        XCTAssertEqual(selectedActive, 3)
        XCTAssertEqual(selectedName, "Backup")

        await repository.clearSource(slot: 3)
        let fallbackActive = await repository.activeSourceIndex()
        let fallbackName = await repository.activeSource().name
        XCTAssertEqual(fallbackActive, 1)
        XCTAssertEqual(fallbackName, "Primary")
    }

    func testSelectingUnconfiguredSlotIsIgnored() async throws {
        let suite = "SiTVATVTests.PlaylistRepository.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Unable to create isolated UserDefaults")
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let repository = PlaylistRepository(defaults: defaults)
        await repository.saveSources([
            PlaylistSource(slot: 2, name: "Only", url: "https://example.com/list.m3u")
        ])

        await repository.selectSource(slot: 4)
        let active = await repository.activeSourceIndex()
        XCTAssertEqual(active, 2)
    }

    func testLoadRecreatesCacheDirectoryIfItDisappearsAfterInit() async throws {
        let suite = "SiTVATVTests.PlaylistRepository.Cache.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Unable to create isolated UserDefaults")
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SiTVATVTests-\(UUID().uuidString)", isDirectory: true)
        let cacheDirectory = root.appendingPathComponent("Playlists", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaylistStubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        PlaylistStubURLProtocol.responseData = Data(
            "#EXTM3U\n#EXTINF:-1 group-title=\"News\",Cache Test\nhttps://example.com/live.m3u8\n".utf8
        )

        let repository = PlaylistRepository(
            defaults: defaults,
            fileManager: fileManager,
            session: session,
            cacheDirectory: cacheDirectory
        )
        await repository.saveSources([
            PlaylistSource(slot: 0, name: "Primary", url: "https://example.com/list.m3u")
        ])
        await repository.selectSource(slot: 0)

        XCTAssertTrue(fileManager.fileExists(atPath: cacheDirectory.path))
        try fileManager.removeItem(at: root)
        XCTAssertFalse(fileManager.fileExists(atPath: cacheDirectory.path))

        let result = try await repository.load()

        XCTAssertEqual(result.channels.count, 1)
        XCTAssertEqual(result.channels.first?.name, "Cache Test")
        XCTAssertFalse(result.fromCache)
        XCTAssertTrue(fileManager.fileExists(atPath: cacheDirectory.path))
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: cacheDirectory.appendingPathComponent("playlist-cache-0.m3u").path
            )
        )
    }
}

private final class PlaylistStubURLProtocol: URLProtocol {
    static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/x-mpegURL"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
