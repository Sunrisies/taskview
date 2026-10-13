import AppKit
import ApplicationServices
import ScreenCaptureKit

/// 权限状态和设置跳转；以实际接口的拒绝错误区分未授权和其他故障。
enum Permissions {
    private static var lastScreenCaptureResult: Bool?
    static var isScreenRecordingTrusted: Bool {
        lastScreenCaptureResult ?? CGPreflightScreenCaptureAccess()
    }

    static func recordScreenCaptureSuccess() { lastScreenCaptureResult = true }

    static func isScreenCaptureDenied(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }

    static func recordScreenCaptureFailure(_ error: Error) {
        if isScreenCaptureDenied(error) { lastScreenCaptureResult = false }
    }

    /// 仅在用户主动点击检查时探测，避免每次应用激活都触发系统授权弹窗。
    @MainActor
    static func verifyScreenRecordingAccess() async -> String? {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            recordScreenCaptureSuccess()
            return nil
        } catch {
            recordScreenCaptureFailure(error)
            return isScreenCaptureDenied(error)
                ? "系统仍拒绝屏幕录制访问。请确认授权的是当前路径的应用，并完全退出后重开。"
                : "权限检查未完成：\(error.localizedDescription)"
        }
    }

    static func requestScreenRecordingAccess() {
        CGRequestScreenCaptureAccess()
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 请求辅助功能授权；系统可能提示用户前往设置。
    static func requestAccessibilityAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openScreenRecordingSettings() {
        openSettingsPane("Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        openSettingsPane("Privacy_Accessibility")
    }

    private static func openSettingsPane(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }
}
