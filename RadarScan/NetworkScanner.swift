import Foundation
import Darwin

/// Nhóm loại máy để tô màu trên radar cho dễ phân biệt.
enum DeviceCategory: String, CaseIterable {
    case router = "Router / Modem"
    case apple = "iPhone / iPad / Mac"
    case windows = "Máy tính Windows"
    case printer = "Máy in"
    case tv = "TV / Chromecast / Apple TV"
    case unknown = "Khác"

    /// Mã hex để dùng chung cho cả SwiftUI Color lẫn mô tả.
    var hex: String {
        switch self {
        case .router: return "#FFC107"   // vàng cam
        case .apple: return "#4DA3FF"    // xanh dương
        case .windows: return "#FF5C5C"  // đỏ
        case .printer: return "#B388FF"  // tím
        case .tv: return "#FF8A3D"       // cam
        case .unknown: return "#4CD964"  // xanh lá (mặc định cũ)
        }
    }
}

struct Device: Identifiable {
    let id = UUID()
    let ip: String
    var name: String
    var kind: String
    var model: String?
    var openPorts: [UInt16] = []
    var services: [String] = []
    var displayKind: String { model ?? kind }
    // Vị trí trên radar chỉ mang tính minh hoạ (iOS không cho biết hướng/khoảng cách thật của thiết bị)
    var last: Int { Int(ip.split(separator: ".").last ?? "1") ?? 1 }
    var angle: Double { Double((last * 37) % 360) }
    var radius: Double { 0.25 + 0.7 * Double(last % 50) / 50.0 }

    var category: DeviceCategory {
        let l = (model ?? kind).lowercased()
        if l.contains("router") || kind == "Router" { return .router }
        if l.contains("iphone") || l.contains("ipad") || l.contains("macbook") || l.contains("imac")
            || l.contains("mac mini") || l.contains("apple watch") { return .apple }
        if l.contains("windows") || kind.contains("Máy tính") && !l.contains("mac") { return .windows }
        if l.contains("máy in") || l.contains("printer") { return .printer }
        if l.contains("tv") || l.contains("chromecast") || l.contains("airplay") { return .tv }
        return .unknown
    }
}

final class NetworkScanner: ObservableObject {
    @Published var devices: [Device] = []
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var localIP = "—"
    @Published var message = "Nhấn Quét để bắt đầu"

    private let bonjour = BonjourDiscovery()
    private let ports: [UInt16] = [80, 443, 62078, 445, 22, 8080, 53, 7000, 5000, 8009, 9100, 548, 139, 8008]

    func start() {
        guard !isScanning else { return }
        guard let ip = Self.localIPv4() else {
            message = "Chưa kết nối WiFi"
            return
        }
        localIP = ip
        devices = []
        progress = 0
        isScanning = true
        message = "Đang quét mạng…"

        bonjour.onFound = { [weak self] ip, name, model, type in
            self?.upsert(ip: ip, name: name, kind: nil, model: model, service: type)
        }
        bonjour.start()

        // Toàn bộ việc tạo hàng trăm tác vụ con (kể cả sem.wait() có thể bị chặn chờ)
        // được đẩy xuống hàng đợi nền, để không làm đứng UI ngay lúc bấm nút Quét.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let base = ip.split(separator: ".").prefix(3).joined(separator: ".")
            let queue = DispatchQueue(label: "scan", qos: .utility, attributes: .concurrent)
            let group = DispatchGroup()
            let sem = DispatchSemaphore(value: 48) // vừa đủ nhanh, không làm máy ì
            let lock = NSLock()
            var done = 0

            for i in 1...254 {
                let target = "\(base).\(i)"
                sem.wait()
                group.enter()
                queue.async {
                    defer { sem.signal(); group.leave() }
                    // Dò 1 lần duy nhất qua tất cả cổng, thay vì dò 2 lần như trước.
                    let openPorts = self.ports.filter { Self.probe(ip: target, port: $0, timeoutMs: 200) }
                    if let first = openPorts.first {
                        let host = Self.hostname(for: target)
                        self.upsert(ip: target, name: host, kind: Self.guessKind(port: first), model: nil, ports: openPorts)
                    } else if ICMPPing.ping(ip: target, timeoutMs: 350) {
                        // Không có cổng nào trong danh sách mở, nhưng máy vẫn trả lời ping —
                        // bắt được các máy tính chặn hết cổng dịch vụ nhưng không chặn ICMP.
                        let host = Self.hostname(for: target)
                        self.upsert(ip: target, name: host, kind: "Thiết bị mạng (chỉ phản hồi ping)", model: nil)
                    }
                    lock.lock(); done += 1; let d = done; lock.unlock()
                    DispatchQueue.main.async { self.progress = Double(d) / 254.0 }
                }
            }
            group.notify(queue: .main) {
                self.message = "Đang đọc thông tin thiết bị…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.bonjour.stop()
                    self.isScanning = false
                    self.devices.sort { $0.last < $1.last }
                    self.message = "Tìm thấy \(self.devices.count) thiết bị"
                }
            }
        }
    }

    func upsert(ip: String, name: String?, kind: String?, model: String?, ports: [UInt16] = [], service: String? = nil) {
        DispatchQueue.main.async {
            let mine = ip == self.localIP
            let nameKind = name.flatMap { Self.kindFromName($0) }
            if let i = self.devices.firstIndex(where: { $0.ip == ip }) {
                if let n = name, !n.isEmpty, (model != nil || self.devices[i].name.hasPrefix("Thiết bị")) { self.devices[i].name = n }
                if let m = model { self.devices[i].model = m }
                if !ports.isEmpty { self.devices[i].openPorts = ports }
                if let sv = service, !self.devices[i].services.contains(sv) { self.devices[i].services.append(sv) }
                if let k = nameKind { self.devices[i].kind = k }
            } else {
                let n = name ?? (mine ? "Thiết bị này" : "Thiết bị \(ip)")
                self.devices.append(Device(ip: ip, name: n, kind: nameKind ?? kind ?? "Thiết bị mạng", model: model,
                                           openPorts: ports, services: service.map { [$0] } ?? []))
            }
        }
    }

    static func kindFromName(_ n: String) -> String? {
        let l = n.lowercased()
        let table = [("iphone", "iPhone"), ("ipad", "iPad"), ("macbook", "MacBook"), ("imac", "iMac"),
                     ("android", "Điện thoại Android"), ("galaxy", "Samsung Galaxy"), ("tv", "TV"),
                     ("printer", "Máy in"), ("watch", "Apple Watch"),
                     ("windows", "Máy tính Windows"), ("desktop-", "Máy tính Windows"), ("-pc", "Máy tính Windows")]
        return table.first { l.contains($0.0) }?.1
    }

    static func guessKind(port: UInt16) -> String {
        switch port {
        case 62078: return "iPhone / iPad"
        case 7000, 5000: return "Apple TV / AirPlay"
        case 8009, 8008: return "Chromecast / TV"
        case 9100: return "Máy in"
        case 445, 139: return "Máy tính Windows / NAS"
        case 548: return "Máy tính Mac / NAS"
        case 53: return "Router"
        case 22: return "Máy chủ / Linux"
        default: return "Thiết bị mạng"
        }
    }

    static func probe(ip: String, port: UInt16, timeoutMs: Int32) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, ip, &addr.sin_addr)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if r == 0 { return true }
        if errno != EINPROGRESS { return errno == ECONNREFUSED }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        if poll(&pfd, 1, timeoutMs) <= 0 { return false }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        return err == 0 || err == ECONNREFUSED
    }

    static func hostname(for ip: String) -> String? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, ip, &addr.sin_addr)
        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &buf, socklen_t(buf.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard r == 0 else { return nil }
        let s = String(cString: buf)
        return s == ip ? nil : s
    }

    static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let p = ptr {
            let i = p.pointee
            if let a = i.ifa_addr, a.pointee.sa_family == UInt8(AF_INET),
               String(cString: i.ifa_name) == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                return String(cString: host)
            }
            ptr = i.ifa_next
        }
        return nil
    }
}
