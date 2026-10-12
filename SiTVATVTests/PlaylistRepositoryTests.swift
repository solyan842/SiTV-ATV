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
}
