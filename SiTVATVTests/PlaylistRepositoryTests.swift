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

        XCTAssertEqual(await repository.configuredSources().map(\.slot), [1, 3])
        XCTAssertEqual(await repository.activeSourceIndex(), 1)

        await repository.selectSource(slot: 3)
        XCTAssertEqual(await repository.activeSourceIndex(), 3)
        XCTAssertEqual(await repository.activeSource().name, "Backup")

        await repository.clearSource(slot: 3)
        XCTAssertEqual(await repository.activeSourceIndex(), 1)
        XCTAssertEqual(await repository.activeSource().name, "Primary")
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
        XCTAssertEqual(await repository.activeSourceIndex(), 2)
    }
}
