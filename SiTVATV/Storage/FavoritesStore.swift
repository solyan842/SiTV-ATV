import Foundation

actor FavoritesStore {
    private let defaults: UserDefaults
    private let key = "favorite_channel_ids"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func channelIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    @discardableResult
    func toggle(channelID: String) -> Set<String> {
        var values = channelIDs()
        if values.contains(channelID) {
            values.remove(channelID)
        } else {
            values.insert(channelID)
        }
        persist(values)
        return values
    }

    @discardableResult
    func setFavorite(_ isFavorite: Bool, channelID: String) -> Set<String> {
        var values = channelIDs()
        if isFavorite {
            values.insert(channelID)
        } else {
            values.remove(channelID)
        }
        persist(values)
        return values
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func persist(_ values: Set<String>) {
        defaults.set(values.sorted(), forKey: key)
    }
}
