import Foundation
import NetworkExtension
import Network

/// Kiểm tra một WiFi: validate thông tin nhập, và (nếu máy có entitlement Hotspot Configuration)
/// thử tự kết nối vào mạng rồi kiểm tra Internet.
final class WifiTester: ObservableObject {
    @Published var isRunning = false
    @Published var log: [String] = []

    func validate(_ p: WifiProfile) -> (ok: Bool, message: String) {
        if p.ssid.trimmingCharacters(in: .whitespaces).isEmpty {
            return (false, "Thiếu tên WiFi")
        }
        if p.security != "nopass" {
            if p.password.isEmpty { return (false, "Thiếu mật khẩu") }
            if p.security == "WPA" && p.password.count < 8 {
                return (false, "Mật khẩu WPA cần tối thiểu 8 ký tự")
            }
            if p.security == "WEP" && ![5, 13, 10, 26].contains(p.password.count) {
                return (false, "Độ dài mật khẩu WEP không hợp lệ")
            }
        }
        return (true, "Thông tin hợp lệ")
    }

    /// Thử tự join mạng (cần entitlement HotspotConfiguration, không phải lúc nào cũng có khi sideload).
    func connectAndCheckInternet(_ p: WifiProfile, completion: @escaping (String, Bool) -> Void) {
        let config: NEHotspotConfiguration
        if p.security == "nopass" {
            config = NEHotspotConfiguration(ssid: p.ssid)
        } else {
            config = NEHotspotConfiguration(ssid: p.ssid, passphrase: p.password, isWEP: p.security == "WEP")
        }
        config.joinOnce = false

        NEHotspotConfigurationManager.shared.apply(config) { [weak self] error in
            if let error = error as NSError? {
                if error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                    self?.checkInternet(ssid: p.ssid, completion: completion)
                } else {
                    completion("Không tự kết nối được (\(error.localizedDescription)). Có thể thiếu quyền Hotspot Configuration — bạn tự vào Cài đặt > WiFi chọn mạng để kiểm tra.", false)
                }
                return
            }
            // Đợi hệ thống chuyển mạng xong rồi kiểm tra Internet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self?.checkInternet(ssid: p.ssid, completion: completion)
            }
        }
    }

    private func checkInternet(ssid: String, completion: @escaping (String, Bool) -> Void) {
        var url = URLRequest(url: URL(string: "https://captive.apple.com/hotspot-detect.html")!)
        url.timeoutInterval = 5
        URLSession.shared.dataTask(with: url) { data, resp, err in
            DispatchQueue.main.async {
                if err == nil, let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    completion("Kết nối OK, có Internet", true)
                } else {
                    completion("Vào được mạng nhưng không có Internet (hoặc đăng nhập cổng chào)", false)
                }
            }
        }.resume()
    }

    /// Kiểm tra lần lượt nhiều WiFi, cập nhật trạng thái vào store.
    func checkAll(_ store: WifiStore, autoConnect: Bool) {
        guard !isRunning else { return }
        isRunning = true
        log = []
        let list = store.profiles
        func step(_ i: Int) {
            guard i < list.count else { self.isRunning = false; return }
            let p = list[i]
            let v = validate(p)
            if !v.ok {
                update(store, ssid: p.ssid, text: v.message, ok: false)
                step(i + 1); return
            }
            guard autoConnect else {
                update(store, ssid: p.ssid, text: "Thông tin hợp lệ", ok: true)
                step(i + 1)
                return
            }
            update(store, ssid: p.ssid, text: "Đang kiểm tra…", ok: nil)
            connectAndCheckInternet(p) { text, ok in
                self.update(store, ssid: p.ssid, text: text, ok: ok)
                step(i + 1)
            }
        }
        step(0)
    }

    private func update(_ store: WifiStore, ssid: String, text: String, ok: Bool?) {
        if let i = store.profiles.firstIndex(where: { $0.ssid == ssid }) {
            store.profiles[i].statusText = text
            store.profiles[i].statusOK = ok
        }
        log.append("\(ssid): \(text)")
    }
}
