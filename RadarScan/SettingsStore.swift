import Foundation

/// Cờ bật/tắt các tính năng. Mặc định tắt tính năng tự kết nối vì hầu hết máy
/// (build sideload) không có entitlement Hotspot Configuration để Apple duyệt.
final class SettingsStore: ObservableObject {
    @Published var autoConnectEnabled: Bool { didSet { UserDefaults.standard.set(autoConnectEnabled, forKey: Self.autoConnectKey) } }

    private static let autoConnectKey = "radarwifi.autoConnectEnabled"

    init() {
        autoConnectEnabled = UserDefaults.standard.bool(forKey: Self.autoConnectKey)
    }
}
