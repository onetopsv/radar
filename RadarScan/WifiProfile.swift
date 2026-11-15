import Foundation

struct WifiProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var ssid: String
    var security: String = "WPA" // WPA | WEP | nopass
    var statusText: String = "Chưa kiểm tra"
    var statusOK: Bool? = nil

    var password: String {
        get { Keychain.load(account: ssid) ?? "" }
        set { Keychain.save(newValue, account: ssid) }
    }
}

/// Lưu danh sách SSID (không lưu mật khẩu ở đây, mật khẩu nằm trong Keychain theo từng SSID).
final class WifiStore: ObservableObject {
    @Published var profiles: [WifiProfile] = [] { didSet { persist() } }
    private let key = "radarwifi.profiles"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([WifiProfile].self, from: data) else { return }
        profiles = list
    }
    func persist() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: key) }
    }
    func add(ssid: String, password: String, security: String) {
        guard !ssid.isEmpty else { return }
        if let i = profiles.firstIndex(where: { $0.ssid == ssid }) {
            profiles[i].security = security
            profiles[i].password = password
        } else {
            var p = WifiProfile(ssid: ssid, security: security)
            p.password = password
            profiles.append(p)
        }
    }
    func remove(at offsets: IndexSet) { profiles.remove(atOffsets: offsets) }
}
