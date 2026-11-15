import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section(header: Text("Kiểm tra WiFi"),
                    footer: Text("Tính năng này cần quyền Hotspot Configuration mà Apple chỉ cấp riêng cho nhà sản xuất thiết bị. Với app cài qua Sideloadly/AltStore, bật lên gần như chắc chắn sẽ không hoạt động và chỉ báo lỗi. Để tắt, app chỉ kiểm tra thông tin bạn nhập có hợp lệ không.")) {
                Toggle("Thử tự kết nối khi kiểm tra", isOn: $settings.autoConnectEnabled)
            }
            Section(header: Text("Thông tin")) {
                HStack { Text("Phiên bản"); Spacer(); Text("1.0").foregroundColor(.gray) }
            }
        }
        .navigationTitle("Cài đặt")
    }
}
