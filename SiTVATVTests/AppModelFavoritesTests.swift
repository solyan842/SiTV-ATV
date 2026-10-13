import XCTest
@testable import SiTVATV

@MainActor
final class AppModelFavoritesTests: XCTestCase {
    func testToggleFavoriteUpdatesModelAndPersists() async throws {
        let suite = "SiTVATVTests.AppModelFavorites.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let favoritesStore = FavoritesStore(defaults: defaults)
        let repository = PlaylistRepository(defaults: defaults)
        let model = AppModel(
            repository: repository,
            favoritesStore: favoritesStore
        )
        let channel = Channel(
            id: "vtv1",
            name: "VTV1",
            group: "VTV",
            logoURL: nil,
            sources: []
        )

        XCTAssertFalse(model.isFavorite(channel))

        await model.toggleFavorite(channel)

        XCTAssertTrue(model.isFavorite(channel))
        let persisted = await favoritesStore.channelIDs()
        XCTAssertEqual(persisted, Set(["vtv1"]))

        await model.toggleFavorite(channel)

        XCTAssertFalse(model.isFavorite(channel))
        let persistedAfterRemove = await favoritesStore.channelIDs()
        XCTAssertTrue(persistedAfterRemove.isEmpty)
    }

    func testBootstrapRestoresFavoriteStateWithoutConfiguredPlaylist() async throws {
        let suite = "SiTVATVTests.AppModelFavorites.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let favoritesStore = FavoritesStore(defaults: defaults)
        _ = await favoritesStore.setFavorite(true, channelID: "vtv1")

        let model = AppModel(
            repository: PlaylistRepository(defaults: defaults),
            favoritesStore: favoritesStore
        )
        await model.bootstrap()

        XCTAssertEqual(model.favoriteChannelIDs, Set(["vtv1"]))
        XCTAssertTrue(model.groups.contains("Yêu thích"))
    }
}
