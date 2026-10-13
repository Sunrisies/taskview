import AppKit
import ApplicationServices

/// 激活目标应用，并复用辅助功能窗口枚举和 AXValue 几何解码来匹配指定窗口。
enum FocusController {
    static func focus(_ item: WindowItem) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        app.activate()
        // 缺少权限时只能激活应用；有权限时必须解码 AXValue，不能直接桥接 CGPoint。
        guard Permissions.isAccessibilityTrusted,
              let windows = try? AXWindowCloseBackend().windows(pid: item.pid),
              let index = WindowMatcher.bestIndex(candidates: windows.map(\.metadata),
                                                   title: item.originalTitle, frame: item.frame) else { return }
        AXUIElementPerformAction(windows[index].element, kAXRaiseAction as CFString)
    }
}
