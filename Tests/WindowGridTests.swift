import AppKit

// 使用替代窗口元数据验证真实网格视图，不进行屏幕录制。

struct WindowItem: WindowMetadata {
    var pid: pid_t = 1
    var frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    let title: String
    let appName: String
    let icon: NSImage
}
enum DebugLog { static func write(_ message: String) {} }

@main
struct WindowGridTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let view = OverlayContentView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        let window = OverlayWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.onKeyDown = { view.keyDown(with: $0) }
        let items = (0..<400).map { WindowItem(title: "Window \($0)", appName: "Test", icon: NSImage(size: NSSize(width: 32, height: 32))) }
        let scroll = view.subviews.compactMap { $0 as? NSScrollView }.first!
        for count in [0, 1, 8, 80, 400] {
            view.setItems(Array(items.prefix(count)))
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            let cells = scroll.documentView!.subviews.compactMap { $0 as? WindowCellView }
            precondition(cells.count == count)
            for cell in cells {
                precondition(cell.frame.width > 0 && cell.frame.height >= 130)
                precondition(scroll.documentView!.bounds.contains(cell.frame), "Cards must stay inside scrollable grid")
                cell.layoutSubtreeIfNeeded()
            }
            if count > 0 {
                view.select(count - 1)
                precondition(scroll.documentVisibleRect.intersects(cells.last!.frame), "Keyboard selection must scroll into view")
            }
        }
        view.setItems(Array(items.prefix(8)))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        func key(_ code: UInt16) {
            view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
        }
        // 复现产品中的窗口转发链，未处理按键必须返回，不能在视图和窗口间递归。
        for code in [UInt16(51), 117, 122] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{7f}",
                charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: code)!
            window.keyDown(with: event)
            precondition(view.selectedIndex == 0)
        }
        // 即使未来回调主动重新进入窗口，防护也保证每次外部按键只转发一次。
        var forwarded = 0
        window.onKeyDown = { event in forwarded += 1; window.keyDown(with: event) }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
        window.keyDown(with: event)
        precondition(forwarded == 1)
        window.onKeyDown = { view.keyDown(with: $0) }
        key(123)
        precondition(view.selectedIndex == 7)
        key(124)
        precondition(view.selectedIndex == 0)
        key(125)
        precondition(view.selectedIndex > 0)
        key(126)
        precondition(view.selectedIndex == 0)
        let cells = scroll.documentView!.subviews.compactMap { $0 as? WindowCellView }
        view.hoverSelection = false
        cells[3].onHover?(3)
        precondition(view.selectedIndex == 0)
        view.hoverSelection = true
        cells[3].onHover?(3)
        precondition(view.selectedIndex == 3)
        var focused: Int?
        view.onFocusSelected = { focused = $0 }
        key(36)
        precondition(focused == 3)
        cells[2].onSelect?(2)
        precondition(focused == 2)
        var closed = false
        view.onCloseRequested = { closed = true }
        key(53)
        precondition(closed)
        closed = false
        view.setSearch("Window 3")
        precondition(view.displayedIndices == [3])
        var closeTarget: Int?
        view.onCloseWindow = { closeTarget = $0 }
        let resultCell = scroll.documentView!.subviews.compactMap { $0 as? WindowCellView }.first!
        let closeButton = resultCell.subviews.compactMap { $0 as? NSButton }.first!
        focused = nil
        closeButton.performClick(nil)
        precondition(closeTarget == 3 && focused == nil, "关闭按钮只发送关闭，不触发打开窗口")
        key(36)
        precondition(focused == 3, "搜索结果必须聚焦原始窗口")
        key(53)
        precondition(!closed && view.displayedIndices.count == 8, "第一次 Esc 清空搜索")
        view.setSearch("不存在的标题")
        focused = nil
        key(36)
        precondition(focused == nil)
        key(53)
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        view.configure(scope: .allDisplays, grouped: true, screenRect: nil)
        view.setItems([WindowItem(pid: 1, title: "Alpha", appName: "Mail", icon: icon),
                       WindowItem(pid: 2, frame: CGRect(x: 2000, y: 0, width: 800, height: 600), title: "Beta", appName: "Browser", icon: icon),
                       WindowItem(pid: 1, title: "Gamma", appName: "Mail", icon: icon)])
        precondition(view.displayedIndices == [0, 2, 1])
        view.select(1)
        key(36)
        precondition(focused == 2, "分组后确认必须保留窗口身份")
        closeTarget = nil
        let closeKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{7f}",
            charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
        view.keyDown(with: closeKey)
        precondition(closeTarget == 2, "分组后的关闭快捷键必须使用原始窗口索引")
        view.configure(scope: .currentDisplay, grouped: true, screenRect: CGRect(x: 0, y: 0, width: 1280, height: 720))
        precondition(view.displayedIndices == [0, 2])
        let visible = view.visibleSourceIndices
        precondition(!visible.contains(1))
        view.configure(scope: .allDisplays, grouped: true, screenRect: nil)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1).cgColor
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        if let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: image)
            if let data = image.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "build/tests/taskview-preview.png"))
            }
        }
        window.orderOut(nil)
        view.setItems([])
        closed = false
        key(53)
        precondition(closed)
        print("PASS: 网格 0/1/8/80/400 窗口布局、导航、搜索原始索引、Esc 清空、应用分组和显示器筛选")
    }
}
