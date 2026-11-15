import SwiftUI
import CoreImage.CIFilterBuiltins

/// Nhập tên + mật khẩu WiFi (lưu Keychain) rồi tạo mã QR để người khác quét kết nối.
struct WifiShareView: View {
    let initialSSID: String
    let status: String
    @State private var ssid = ""
    @State private var password = ""
    @State private var security = "WPA"
    @State private var showPassword = false
    @Environment(\.presentationMode) private var presentation

    var payload: String {
        func esc(_ s: String) -> String {
            var r = s
            for c in ["\\", ";", ",", "\"", ":"] { r = r.replacingOccurrences(of: c, with: "\\" + c) }
            return r
        }
        if security == "nopass" { return "WIFI:T:nopass;S:\(esc(ssid));;" }
        return "WIFI:T:\(security);S:\(esc(ssid));P:\(esc(password));;"
    }

    func qrImage(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Mạng WiFi"), footer: Text(status)) {
                    TextField("Tên WiFi (SSID)", text: $ssid)
                        .autocapitalization(.none).disableAutocorrection(true)
                    Picker("Bảo mật", selection: $security) {
                        Text("WPA/WPA2").tag("WPA")
                        Text("WEP").tag("WEP")
                        Text("Không có").tag("nopass")
                    }.pickerStyle(.segmented)
                    if security != "nopass" {
                        HStack {
                            Group {
                                if showPassword { TextField("Mật khẩu", text: $password) }
                                else { SecureField("Mật khẩu", text: $password) }
                            }
                            .autocapitalization(.none).disableAutocorrection(true)
                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                            }.buttonStyle(.borderless)
                        }
                    }
                    Button("Lưu mật khẩu vào Keychain") {
                        if !ssid.isEmpty { Keychain.save(password, account: ssid) }
                    }
                }
                if !ssid.isEmpty, let img = qrImage(payload) {
                    Section(header: Text("Mã QR kết nối")) {
                        HStack {
                            Spacer()
                            Image(uiImage: img).interpolation(.none).resizable()
                                .frame(width: 220, height: 220)
                                .padding(8).background(Color.white).cornerRadius(8)
                            Spacer()
                        }
                        Text("Mở Camera trên điện thoại khác và quét mã để kết nối.")
                            .font(.footnote).foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Chia sẻ WiFi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { presentation.wrappedValue.dismiss() }
                }
            }
            .onAppear {
                ssid = initialSSID
                if let pw = Keychain.load(account: ssid) { password = pw }
            }
            .onChange(of: ssid) { new in
                if let pw = Keychain.load(account: new) { password = pw }
            }
        }
    }
}
