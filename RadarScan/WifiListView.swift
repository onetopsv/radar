import SwiftUI

struct WifiListView: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var store = WifiStore()
    @StateObject private var tester = WifiTester()
    @State private var showAdd = false
    @State private var qrFor: WifiProfile?

    var body: some View {
        List {
            Section(footer: Text(settings.autoConnectEnabled
                ? "Kiểm tra tất cả sẽ xem thông tin (SSID, mật khẩu) có hợp lệ không, và thử tự vào từng mạng để kiểm tra Internet. Tính năng tự kết nối cần quyền đặc biệt do Apple duyệt nên có thể báo lỗi."
                : "Kiểm tra tất cả sẽ xem thông tin (SSID, mật khẩu) có hợp lệ không. Bật \"Thử tự kết nối\" trong Cài đặt nếu muốn app thử tự vào từng mạng.")) {
                ForEach(store.profiles) { p in
                    HStack {
                        statusIcon(p.statusOK)
                        VStack(alignment: .leading) {
                            Text(p.ssid)
                            Text(p.statusText).font(.caption).foregroundColor(.gray)
                        }
                        Spacer()
                        Button { qrFor = p } label: {
                            Image(systemName: "qrcode").foregroundColor(.green)
                        }.buttonStyle(.borderless)
                    }
                }
                .onDelete { store.remove(at: $0) }
            }
        }
        .navigationTitle("Danh sách WiFi")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                tester.checkAll(store, autoConnect: settings.autoConnectEnabled)
            } label: {
                Text(tester.isRunning ? "Đang kiểm tra…" : "KIỂM TRA TẤT CẢ (\(store.profiles.count))")
                    .font(.system(.headline, design: .monospaced))
                    .frame(maxWidth: .infinity).padding()
                    .background(tester.isRunning || store.profiles.isEmpty ? Color.gray.opacity(0.4) : Color.green)
                    .foregroundColor(.black)
            }
            .disabled(tester.isRunning || store.profiles.isEmpty)
        }
        .sheet(isPresented: $showAdd) { AddWifiView(store: store) }
        .sheet(item: $qrFor) { p in
            WifiShareView(initialSSID: p.ssid, status: "").preferredColorScheme(.dark)
        }
    }

    @ViewBuilder func statusIcon(_ ok: Bool?) -> some View {
        switch ok {
        case .some(true): Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .some(false): Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case .none: Image(systemName: "circle.dashed").foregroundColor(.gray)
        }
    }
}

struct AddWifiView: View {
    @ObservedObject var store: WifiStore
    @State private var ssid = ""
    @State private var password = ""
    @State private var security = "WPA"
    @Environment(\.presentationMode) private var presentation

    var body: some View {
        NavigationView {
            Form {
                TextField("Tên WiFi (SSID)", text: $ssid)
                    .autocapitalization(.none).disableAutocorrection(true)
                Picker("Bảo mật", selection: $security) {
                    Text("WPA/WPA2").tag("WPA")
                    Text("WEP").tag("WEP")
                    Text("Không có").tag("nopass")
                }.pickerStyle(.segmented)
                if security != "nopass" {
                    SecureField("Mật khẩu", text: $password)
                        .autocapitalization(.none).disableAutocorrection(true)
                }
            }
            .navigationTitle("Thêm WiFi")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Huỷ") { presentation.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lưu") {
                        store.add(ssid: ssid, password: password, security: security)
                        presentation.wrappedValue.dismiss()
                    }.disabled(ssid.isEmpty)
                }
            }
        }
    }
}
