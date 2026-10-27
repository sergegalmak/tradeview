import Foundation

protocol AppPreferenceStore {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

struct UserDefaultsPreferenceStore: AppPreferenceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}
