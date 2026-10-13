import AppKit

/// 可接收键盘焦点的无边框覆盖窗口。
final class OverlayWindow: NSWindow {
    /// 当响应链没有把按键交给网格时，由窗口转发，避免方向键或退出键失效。
    var onKeyDown: ((NSEvent) -> Void)?
    private var isForwardingKey = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        // 内容视图的响应链可能把未处理按键再次交回窗口，禁止转发同一个调用栈。
        guard !isForwardingKey else { return }
        if let onKeyDown {
            isForwardingKey = true
            defer { isForwardingKey = false }
            onKeyDown(event)
        } else {
            super.keyDown(with: event)
        }
    }
}
