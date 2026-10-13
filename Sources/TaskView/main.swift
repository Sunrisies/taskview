import AppKit

let app = NSApplication.shared
// AppKit 在主执行器上运行；委托由此作用域持有，覆盖整个应用事件循环。
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // 等待系统事件，不创建轮询定时器；菜单栏工具不显示 Dock 图标。
    app.run()
}
