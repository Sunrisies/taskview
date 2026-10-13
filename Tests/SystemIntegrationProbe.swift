import AppKit
import Carbon.HIToolbox
import ServiceManagement

// 读取真实权限状态，并短暂尝试注册一个少用快捷键；不请求权限、修改登录项或读取偏好。
@main
struct SystemIntegrationProbe {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_J),
            UInt32(cmdKey | optionKey | controlKey | shiftKey),
            EventHotKeyID(signature: 0x5456_5052, id: 1),
            GetEventDispatcherTarget(), 0, &reference)
        if let reference { UnregisterEventHotKey(reference) }
        let report: [String: Any] = [
            "hotKeyStatus": status,
            "loginItemStatus": SMAppService.mainApp.status.rawValue,
            "screenRecordingGranted": CGPreflightScreenCaptureAccess(),
            "accessibilityGranted": AXIsProcessTrusted(),
            "bundlePath": Bundle.main.bundlePath
        ]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }
}
