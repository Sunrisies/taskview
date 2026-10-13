import AppKit
import ApplicationServices

/// 关闭操作只传递不可变窗口元信息，不把视图或截图对象传到后台线程。
struct WindowCloseTarget: Sendable {
    let pid: pid_t
    let title: String?
    let frame: CGRect
}

enum WindowCloseError: Error, LocalizedError, Equatable, Sendable {
    case permissionRequired
    case windowChanged
    case unsupported
    case disabled
    case system(Int32)
    var errorDescription: String? {
        switch self {
        case .permissionRequired: return "关闭窗口需要辅助功能权限，请在系统设置中允许当前 TaskView。"
        case .windowChanged: return "未能唯一确认目标窗口，窗口可能已关闭、移动或更改标题。请重新打开任务视图后再试。"
        case .unsupported: return "此窗口没有提供可操作的关闭按钮。"
        case .disabled: return "目标应用的关闭按钮暂时不可用，可能正在显示对话框。"
        case .system(let code): return "目标应用未能完成关闭请求（辅助功能错误码：\(code)）。"
        }
    }
}

struct AccessibleWindow<Element> {
    let element: Element
    let metadata: WindowMatcher.Candidate
}

/// 替代接口用于测试关闭行为，不关闭测试机器中的真实窗口。
protocol WindowCloseBackend {
    associatedtype Element
    var isTrusted: Bool { get }
    func windows(pid: pid_t) throws -> [AccessibleWindow<Element>]
    func pressCloseButton(window: Element) throws
}

enum WindowCloseService {
    static func close<Backend: WindowCloseBackend>(_ target: WindowCloseTarget, using backend: Backend) throws {
        guard backend.isTrusted else { throw WindowCloseError.permissionRequired }
        let windows = try backend.windows(pid: target.pid)
        // 关闭比聚焦更严格：必须几何匹配；双方有标题时必须完全一致，不采用前缀猜测。
        guard let index = WindowMatcher.closeIndex(candidates: windows.map(\.metadata),
                                                   title: target.title, frame: target.frame) else {
            throw WindowCloseError.windowChanged
        }
        try backend.pressCloseButton(window: windows[index].element)
    }
}

/// 使用原生关闭按钮的 AXPress 动作，保留目标应用自己的保存确认和取消行为。
struct AXWindowCloseBackend: WindowCloseBackend {
    var isTrusted: Bool { AXIsProcessTrusted() }
    func windows(pid: pid_t) throws -> [AccessibleWindow<AXUIElement>] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard status == .success else { throw WindowCloseError.system(status.rawValue) }
        guard let windows = value as? [AXUIElement] else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        return try windows.compactMap { window in
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw WindowCloseError.system(AXError.cannotComplete.rawValue)
            }
            AXUIElementSetMessagingTimeout(window, 1)
            guard let frame = Self.windowFrame(position: attribute(kAXPositionAttribute, element: window),
                                               size: attribute(kAXSizeAttribute, element: window)) else { return nil }
            return AccessibleWindow(element: window, metadata: WindowMatcher.Candidate(
                title: attribute(kAXTitleAttribute, element: window) as? String,
                frame: frame))
        }
    }

    func pressCloseButton(window: AXUIElement) throws {
        guard let value = attribute(kAXCloseButtonAttribute, element: window),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { throw WindowCloseError.unsupported }
        let button = value as! AXUIElement
        AXUIElementSetMessagingTimeout(button, 1)
        if let enabled = attribute(kAXEnabledAttribute, element: button) as? Bool, !enabled {
            throw WindowCloseError.disabled
        }
        let status = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard status == .success else { throw WindowCloseError.system(status.rawValue) }
    }

    private func attribute(_ name: String, element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    /// AX 返回 AXValue，显式解码 CGPoint / CGSize，不能直接假设能桥接成 Swift 几何值。
    static func windowFrame(position: CFTypeRef?, size: CFTypeRef?) -> CGRect? {
        guard let position, let size, CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let positionValue = position as! AXValue
        let sizeValue = size as! AXValue
        guard AXValueGetType(positionValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize else { return nil }
        var point = CGPoint.zero
        var decodedSize = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &decodedSize) else { return nil }
        return CGRect(origin: point, size: decodedSize)
    }
}
