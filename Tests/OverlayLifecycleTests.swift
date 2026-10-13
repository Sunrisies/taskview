import AppKit

// 用替代系统服务验证加载取消和回调竞态，不请求权限，也不展示全屏窗口。
struct WindowItem {
    let scWindow: Int
    var pid: pid_t { 1 }
    var originalTitle: String? { nil }
    var frame: CGRect { .zero }
}
@MainActor
enum WindowList {
    static var requests: [CheckedContinuation<[WindowItem], Error>] = []
    static func fetch() async throws -> [WindowItem] {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }
}
enum Permissions {
    // 预检查为假时，仍必须允许实际接口读取尝试。
    static var isScreenRecordingTrusted: Bool { false }
    static func recordScreenCaptureSuccess() {}
    static func recordScreenCaptureFailure(_ error: Error) {}
    static func isScreenCaptureDenied(_ error: Error) -> Bool { false }
    static func openScreenRecordingSettings() {}
    static var isAccessibilityTrusted: Bool { false }
    static func openAccessibilitySettings() {}
}
enum DebugLog { static func write(_ message: String) {} }
enum ThumbnailService {
    static func capture(_ window: Int) async throws -> NSImage { NSImage() }
}
enum FocusController { static func focus(_ item: WindowItem) {} }
final class OverlayContentView: NSView {
    var hoverSelection = true
    var visibleSourceIndices: [Int] { [] }
    var onVisibleIndicesChanged: (([Int]) -> Void)?
    var onScopeChanged: ((WindowScope) -> Void)?
    var onGroupingChanged: ((Bool) -> Void)?
    var items: [WindowItem] = []
    var onFocusSelected: ((Int) -> Void)?
    var onCloseRequested: (() -> Void)?
    var onCloseWindow: ((Int) -> Void)?
    func setItems(_ items: [WindowItem]) { self.items = items }
    func setThumbnail(_ image: NSImage?, at index: Int) {}
    func configure(scope: WindowScope, grouped: Bool, screenRect: CGRect?) {}
}

@main
struct OverlayLifecycleTests {
    @MainActor
    static func settle() async {
        // 给主执行器和异步恢复回调时间运行。
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    @MainActor
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    @MainActor
    static func main() async {
        let overlay = OverlayController()

        overlay.toggle()
        overlay.toggle()
        await settle()
        expect(WindowList.requests.isEmpty, "Immediate cancellation must not start a fetch")

        overlay.show()
        await settle()
        expect(WindowList.requests.count == 1, "Showing starts one fetch")
        overlay.show()
        await settle()
        expect(WindowList.requests.count == 1, "Duplicate show must not start another fetch")

        overlay.toggle()
        overlay.show()
        await settle()
        expect(WindowList.requests.count == 2, "Cancelled loading must allow a fresh show")

        // 旧请求在新请求加载时返回，不能弹出覆盖层，也不能清除新请求的加载状态。
        WindowList.requests[0].resume(returning: [])
        await settle()
        expect(!overlay.isVisible, "Stale success must not display the overlay")
        overlay.show()
        await settle()
        expect(WindowList.requests.count == 2, "Stale success must not reset newer loading state")

        overlay.hide()
        WindowList.requests[1].resume(throwing: CocoaError(.fileReadUnknown))
        await settle()
        expect(!overlay.isVisible, "Cancelled failure must not display the overlay or an alert")

        overlay.show()
        await settle()
        expect(WindowList.requests.count == 3, "Loading must recover after cancellation")
        overlay.hide()
        WindowList.requests[2].resume(returning: [])
        await settle()
        expect(!overlay.isVisible, "Hidden overlay must stay hidden when fetching completes")
        print("PASS: immediate cancellation, duplicate show, stale completion, cancelled failure, reload")
    }
}
