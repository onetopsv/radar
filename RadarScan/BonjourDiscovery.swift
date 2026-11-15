import Foundation
import Darwin

/// Dùng Bonjour/mDNS để đọc tên và mã model (vd "iPhone12,1" -> "iPhone 11") nếu thiết bị có công bố.
final class BonjourDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let types = ["_companion-link._tcp.", "_device-info._tcp.", "_airplay._tcp.", "_raop._tcp.",
                        "_googlecast._tcp.", "_ipp._tcp.", "_hap._tcp.", "_apple-mobdev2._tcp.", "_smb._tcp."]
    var onFound: ((String, String, String?, String) -> Void)?
    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []

    func start() {
        DispatchQueue.main.async {
            for t in Self.types {
                let b = NetServiceBrowser()
                b.delegate = self
                b.searchForServices(ofType: t, inDomain: "local.")
                self.browsers.append(b)
            }
        }
    }

    func stop() {
        browsers.forEach { $0.stop() }
        browsers = []
        services = []
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        var ip: String?
        for data in sender.addresses ?? [] {
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                let sa = base.assumingMemoryBound(to: sockaddr.self)
                if sa.pointee.sa_family == UInt8(AF_INET) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(sa, socklen_t(data.count), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    ip = String(cString: host)
                }
            }
        }
        guard let ip = ip else { return }
        var model: String?
        if let txt = sender.txtRecordData() {
            let d = NetService.dictionary(fromTXTRecord: txt)
            for key in ["rpMd", "model", "am", "md"] {
                if let v = d[key], let str = String(data: v, encoding: .utf8), !str.isEmpty {
                    model = Self.friendlyModel(str); break
                }
            }
        }
        onFound?(ip, sender.name, model, sender.type)
    }

    static let iPhones: [String: String] = [
        "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X", "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR", "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2020)", "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,6": "iPhone SE (2022)", "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e"
    ]

    static func friendlyModel(_ raw: String) -> String {
        if let n = iPhones[raw] { return n }
        let prefixes = [("iPhone", "iPhone"), ("iPad", "iPad"), ("MacBookPro", "MacBook Pro"), ("MacBookAir", "MacBook Air"),
                        ("MacBook", "MacBook"), ("Macmini", "Mac mini"), ("iMac", "iMac"), ("Mac", "Mac"),
                        ("AppleTV", "Apple TV"), ("AudioAccessory", "HomePod"), ("Watch", "Apple Watch")]
        for (p, n) in prefixes where raw.hasPrefix(p) { return n }
        return raw
    }
}
