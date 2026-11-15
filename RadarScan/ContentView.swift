import SwiftUI

extension Color {
    /// Khởi tạo Color từ chuỗi hex dạng "#RRGGBB".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s.removeAll { $0 == "#" }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255)
    }
}

struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()
    @State private var spin = false
    @State private var selected: Device?
    @StateObject private var wifi = WiFiInfo()
    @StateObject private var settings = SettingsStore()
    @State private var showShare = false

    // Trạng thái phóng to / kéo trên radar
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    var body: some View {
        NavigationView { VStack(spacing: 16) {
            Text("RADAR WIFI")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
            Text("IP của bạn: \(scanner.localIP)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.green.opacity(0.7))

            HStack(spacing: 8) {
                Image(systemName: "wifi").foregroundColor(.green)
                Text(wifi.ssid.map { "WiFi: \($0)" } ?? "WiFi: chưa đọc được tên")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.green.opacity(0.9))
                Button { showShare = true } label: {
                    Image(systemName: "qrcode").foregroundColor(.green)
                }
                Spacer()
                NavigationLink(destination: WifiListView(settings: settings).preferredColorScheme(.dark)) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                        Text("Danh sách WiFi")
                    }.font(.footnote).foregroundColor(.green)
                }
                NavigationLink(destination: SettingsView(settings: settings).preferredColorScheme(.dark)) {
                    Image(systemName: "gearshape").foregroundColor(.green)
                }
            }
            .padding(.horizontal)
            .sheet(isPresented: $showShare) {
                WifiShareView(initialSSID: wifi.ssid ?? "", status: wifi.status)
                    .preferredColorScheme(.dark)
            }

            radar
                .frame(height: 320)
                .clipped()
                .padding(.horizontal)
            legend.padding(.horizontal)
            HStack {
                Spacer()
                Button { withAnimation(.spring()) { zoom = 1; panOffset = .zero; lastPan = .zero; lastZoom = 1 } } label: {
                    Label("Về mặc định", systemImage: "arrow.counterclockwise")
                        .font(.caption).foregroundColor(.green.opacity(0.8))
                }
            }.padding(.horizontal)

            ProgressView(value: scanner.progress).tint(.green).padding(.horizontal)
            Text(scanner.message).font(.footnote).foregroundColor(.gray)

            Button(action: { scanner.start() }) {
                Text(scanner.isScanning ? "Đang quét…" : "QUÉT")
                    .font(.system(.headline, design: .monospaced))
                    .frame(maxWidth: .infinity).padding()
                    .background(scanner.isScanning ? Color.gray.opacity(0.4) : Color.green)
                    .foregroundColor(.black).cornerRadius(12)
            }
            .disabled(scanner.isScanning).padding(.horizontal)

            List(scanner.devices) { d in
                Button { selected = d } label: {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right").foregroundColor(Color(hex: d.category.hex))
                        VStack(alignment: .leading) {
                            Text(d.name).font(.subheadline).foregroundColor(.white)
                            Text("\(d.displayKind) • \(d.ip)").font(.caption).foregroundColor(.gray)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
                    }
                }
                .listRowBackground(Color.white.opacity(0.05))
            }
            .listStyle(.plain)
        }
        .padding(.top)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            wifi.refresh()
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) { spin = true }
        }
        .sheet(item: $selected) { d in
            DeviceDetailView(device: scanner.devices.first { $0.ip == d.ip } ?? d)
                .preferredColorScheme(.dark)
        }
        .navigationBarHidden(true)
        }
    }

    var radar: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size / 2

            let magnify = MagnificationGesture()
                .onChanged { v in zoom = min(max(lastZoom * v, 1), 6) }
                .onEnded { _ in lastZoom = zoom }
            let drag = DragGesture()
                .onChanged { v in
                    panOffset = CGSize(width: lastPan.width + v.translation.width,
                                       height: lastPan.height + v.translation.height)
                }
                .onEnded { _ in lastPan = panOffset }

            ZStack {
                ForEach(1..<5) { i in
                    Circle().stroke(Color.green.opacity(0.35), lineWidth: 1)
                        .frame(width: size * CGFloat(i) / 4, height: size * CGFloat(i) / 4)
                }
                Rectangle().fill(Color.green.opacity(0.35)).frame(width: 1, height: size)
                Rectangle().fill(Color.green.opacity(0.35)).frame(width: size, height: 1)

                Circle()
                    .fill(AngularGradient(
                        gradient: Gradient(colors: [.green.opacity(0), .green.opacity(0.55)]),
                        center: .center, startAngle: .degrees(0), endAngle: .degrees(70)))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .opacity(scanner.isScanning ? 1 : 0.35)
                    .allowsHitTesting(false)

                ForEach(scanner.devices) { d in
                    let rad = Angle.degrees(d.angle).radians
                    let color = Color(hex: d.category.hex)
                    ZStack {
                        Circle().fill(Color.clear).frame(width: 36, height: 36) // vùng chạm rộng hơn
                        Circle().fill(color).frame(width: 10, height: 10)
                            .shadow(color: color, radius: 6)
                    }
                    .contentShape(Circle())
                    .onTapGesture { selected = d }
                    .offset(x: CGFloat(cos(rad) * d.radius) * r,
                            y: CGFloat(sin(rad) * d.radius) * r)
                    .transition(.scale)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(zoom)
            .offset(panOffset)
            .gesture(SimultaneousGesture(magnify, drag))
            .animation(.spring(), value: scanner.devices.count)
            .animation(.interactiveSpring(), value: zoom)
        }
    }

    var legend: some View {
        let items: [DeviceCategory] = [.router, .apple, .windows, .printer, .tv, .unknown]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items, id: \.self) { c in
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: c.hex)).frame(width: 9, height: 9)
                        Text(c.rawValue).font(.caption2).foregroundColor(.gray)
                    }
                }
            }
        }
    }
}

struct DeviceDetailView: View {
    let device: Device
    @Environment(\.presentationMode) private var presentation

    static let portNames: [UInt16: String] = [
        80: "HTTP", 443: "HTTPS", 62078: "iPhone (lockdown)", 445: "SMB", 22: "SSH", 8080: "HTTP-alt",
        53: "DNS", 7000: "AirPlay", 5000: "AirPlay/UPnP", 8009: "Chromecast", 8008: "Chromecast",
        9100: "Máy in (RAW)", 548: "AFP", 139: "NetBIOS"
    ]

    func serviceName(_ t: String) -> String {
        t.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "._tcp.", with: "")
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Thiết bị")) {
                    row("Tên", device.name)
                    row("Loại máy", device.displayKind)
                    if let m = device.model, m != device.kind { row("Nhận dạng", m) }
                    row("Địa chỉ IP", device.ip)
                }
                Section(header: Text("Cổng đang mở")) {
                    if device.openPorts.isEmpty {
                        Text("Không có dữ liệu").foregroundColor(.gray)
                    } else {
                        ForEach(device.openPorts, id: \.self) { p in
                            row("\(p)", Self.portNames[p] ?? "Dịch vụ")
                        }
                    }
                }
                if !device.services.isEmpty {
                    Section(header: Text("Dịch vụ Bonjour")) {
                        ForEach(device.services, id: \.self) { Text(serviceName($0)) }
                    }
                }
                Section {
                    Button("Sao chép địa chỉ IP") { UIPasteboard.general.string = device.ip }
                }
                Section(footer: Text("Vị trí chấm trên radar chỉ mang tính minh hoạ, iOS không cung cấp hướng hay khoảng cách thật của thiết bị.")) {
                    EmptyView()
                }
            }
            .navigationTitle(device.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { presentation.wrappedValue.dismiss() }
                }
            }
        }
    }

    func row(_ a: String, _ b: String) -> some View {
        HStack { Text(a).foregroundColor(.gray); Spacer(); Text(b).multilineTextAlignment(.trailing) }
    }
}
