import XCTest
@testable import SiTVATV

final class FavoritesStoreTests: XCTestCase {
    func testTogglePersistsFavoriteIDs() async throws {
        let suite = try XCTUnwrap("SiTVATVTests.FavoritesStore.\(UUID().uuidString)")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FavoritesStore(defaults: defaults)

        let afterAdd = await store.toggle(channelID: "vtv1")
        let persistedAfterAdd = await store.channelIDs()
        XCTAssertEqual(afterAdd, Set(["vtv1"]))
        XCTAssertEqual(persistedAfterAdd, Set(["vtv1"]))

        let afterRemove = await store.toggle(channelID: "vtv1")
        let persistedAfterRemove = await store.channelIDs()
        XCTAssertTrue(afterRemove.isEmpty)
        XCTAssertTrue(persistedAfterRemove.isEmpty)
    }

    func testSetFavoriteIsIdempotent() async throws {
        let suite = try XCTUnwrap("SiTVATVTests.FavoritesStore.\(UUID().uuidString)")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FavoritesStore(defaults: defaults)

        _ = await store.setFavorite(true, channelID: "vtv1")
        _ = await store.setFavorite(true, channelID: "vtv1")
        let ids = await store.channelIDs()

        XCTAssertEqual(ids, Set(["vtv1"]))
    }
}
