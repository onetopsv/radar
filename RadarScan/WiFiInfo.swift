import Foundation
import NetworkExtension
import CoreLocation
import Security

/// Đọc tên WiFi hiện tại (cần quyền Vị trí + entitlement Access WiFi Information).
final class WiFiInfo: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var ssid: String?
    @Published var status = ""
    private let lm = CLLocationManager()

    override init() {
        super.init()
        lm.delegate = self
    }

    func refresh() {
        switch lm.authorizationStatus {
        case .notDetermined: lm.requestWhenInUseAuthorization()
        case .denied, .restricted: status = "Chưa cấp quyền Vị trí nên không đọc được tên WiFi."
        default: fetch()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { refresh() }

    private func fetch() {
        NEHotspotNetwork.fetchCurrent { net in
            DispatchQueue.main.async {
                self.ssid = net?.ssid
                self.status = net == nil
                    ? "Không đọc được tên WiFi (có thể do cài bằng IPA không ký, thiếu entitlement). Bạn có thể nhập tay."
                    : ""
            }
        }
    }
}

enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "radarwifi.wifi",
         kSecAttrAccount as String: account]
    }
    static func save(_ password: String, account: String) {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
    static func load(account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
