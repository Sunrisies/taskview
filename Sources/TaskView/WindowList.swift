import AppKit
import ScreenCaptureKit

/// 网格中的窗口数据，保存截图来源及聚焦匹配所需的元信息。
struct WindowItem: WindowMetadata {
    let windowID: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let originalTitle: String?
    let frame: CGRect
    let icon: NSImage
    let scWindow: SCWindow
}

enum WindowList {
    /// 获取当前可见的普通窗口，排除本应用；权限和系统错误交由调用方分别处理。
    static func fetch() async throws -> [WindowItem] {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: true)
        let ownPID = getpid()
        let workspace = NSWorkspace.shared
        // 同一应用的多个窗口共用图标；缓存仅在这次读取期间存在，不长期保留。
        var icons: [pid_t: NSImage] = [:]

        let items = content.windows.compactMap { window -> WindowItem? in
            guard let owner = window.owningApplication else { return nil }
            guard owner.processID != ownPID else { return nil }
            guard window.windowLayer == 0 else { return nil }
            guard window.isOnScreen else { return nil }
            guard window.frame.width >= 160, window.frame.height >= 100 else { return nil }

            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let appIcon = icons[owner.processID] ?? icon(for: owner, workspace: workspace)
            icons[owner.processID] = appIcon
            return WindowItem(windowID: window.windowID,
                              pid: owner.processID,
                              appName: owner.applicationName,
                              title: title.isEmpty ? owner.applicationName : title,
                              originalTitle: window.title,
                              frame: window.frame,
                              icon: appIcon,
                              scWindow: window)
        }

        // 截图框架没有保证窗口数组的前后顺序，因此另取窗口服务器的顺序排序。
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return items }
        var positions: [CGWindowID: Int] = [:]
        for (index, info) in windowInfo.enumerated() {
            if let number = info[kCGWindowNumber as String] as? NSNumber {
                positions[number.uint32Value] = index
            }
        }
        return items.enumerated().sorted { lhs, rhs in
            let left = positions[lhs.element.windowID] ?? Int.max
            let right = positions[rhs.element.windowID] ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    private static func icon(for owner: SCRunningApplication, workspace: NSWorkspace) -> NSImage {
        if let url = workspace.urlForApplication(withBundleIdentifier: owner.bundleIdentifier) {
            return workspace.icon(forFile: url.path)
        }
        if let app = NSRunningApplication(processIdentifier: owner.processID),
           let url = app.bundleURL {
            return workspace.icon(forFile: url.path)
        }
        let image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 64, height: 64))
        image.size = NSSize(width: 64, height: 64)
        return image
    }
}
