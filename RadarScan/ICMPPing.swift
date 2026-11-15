import Foundation
import Darwin

/// Ping ICMP đơn giản. Trên Darwin (iOS/macOS), socket ICMP kiểu SOCK_DGRAM không cần quyền root
/// (đây là cách Apple dùng trong mẫu "SimplePing" của họ), nên app thường vẫn dùng được.
enum ICMPPing {
    private static func checksum(_ data: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i < data.count - 1 {
            sum += UInt32(data[i]) << 8 | UInt32(data[i + 1])
            i += 2
        }
        if data.count % 2 == 1 { sum += UInt32(data[data.count - 1]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum & 0xffff)
    }

    /// Gửi 1 gói ICMP Echo Request tới ip, chờ tối đa timeoutMs mili-giây.
    static func ping(ip: String, timeoutMs: Int32) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var tv = timeval(tv_sec: timeoutMs / 1000, tv_usec: (timeoutMs % 1000) * 1000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return false }

        let identifier = UInt16.random(in: 0...UInt16.max)
        var packet: [UInt8] = [8, 0, 0, 0] // type=8 (echo request), code=0, checksum placeholder
        packet += [UInt8(identifier >> 8), UInt8(identifier & 0xff)]
        packet += [0, 1] // sequence
        packet += Array("radarwifi".utf8)
        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xff)

        let sent = withUnsafePointer(to: &addr) { ptr -> Int in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                packet.withUnsafeBytes { buf in
                    sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { return false }

        var buffer = [UInt8](repeating: 0, count: 128)
        let received = recv(fd, &buffer, buffer.count, 0)
        guard received > 0 else { return false }
        // Gói trả về có header IP (thường 20 byte) rồi tới ICMP; bỏ qua việc parse chi tiết,
        // chỉ cần nhận được phản hồi trong thời gian chờ là coi như máy đó đang online.
        return true
    }
}
