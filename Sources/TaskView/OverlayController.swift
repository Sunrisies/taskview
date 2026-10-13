import AppKit
import ApplicationServices

/// 管理覆盖层生命周期，协调异步窗口加载、截图和目标窗口聚焦。
@MainActor
final class OverlayController {
    private var window: OverlayWindow?
    private var content: OverlayContentView?
    private var dimming: NSView?
    private let thumbnails = ThumbnailLoader<WindowItem> { item in
        try await ThumbnailService.capture(item.scWindow)
    }
    private var loadTask: Task<Void, Never>?
    private var isLoading = false
    private var isPresentingAlert = false
    private var isClosingWindow = false
    /// 每次打开或取消都会更新；异步回调只允许修改所属版本的界面。
    private var generation = 0
    private(set) var isVisible = false

    func toggle() {
        (isVisible || isLoading) ? hide() : show()
    }

    func show() {
        guard !isVisible, !isLoading, !isPresentingAlert, !isClosingWindow else { return }
        // 先查询实际使用的窗口读取接口；预检查结果不能单独阻止打开。
        DebugLog.write("show: permission indication=\(Permissions.isScreenRecordingTrusted)")

        generation += 1
        let gen = generation
        isLoading = true

        // 获取窗口列表后才显示覆盖层，避免遮挡系统授权弹窗。
        loadTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                let items = try await WindowList.fetch()
                guard !Task.isCancelled, gen == self.generation else { return }
                Permissions.recordScreenCaptureSuccess()
                self.isLoading = false
                self.loadTask = nil
                DebugLog.write("show: fetched \(items.count) windows")
                NSLog("TaskView: fetched \(items.count) windows")
                self.display(items: items, generation: gen)
            } catch {
                guard !Task.isCancelled, gen == self.generation else { return }
                self.isLoading = false
                self.loadTask = nil
                DebugLog.write("show: fetch failed: \(error)")
                NSLog("TaskView: window fetch failed: \(error)")
                Permissions.recordScreenCaptureFailure(error)
                if Permissions.isScreenCaptureDenied(error) {
                    self.presentPermissionAlert()
                } else {
                    self.presentLoadError(error)
                }
            }
        }
    }

    private func display(items: [WindowItem], generation: Int) {
        let screen = targetScreen()
        DebugLog.write("display: screen=\(screen.frame) mouse=\(NSEvent.mouseLocation)")
        buildWindowIfNeeded()

        guard let window, let content else { return }

        window.setFrame(screen.frame, display: true)
        dimming?.layer?.backgroundColor = NSColor.black.withAlphaComponent(
            AppSettings.shared.preferences.backgroundOpacity).cgColor
        content.hoverSelection = AppSettings.shared.preferences.hoverSelection
        let prefs = AppSettings.shared.preferences
        let screenRect = WindowQuery.screenRect(appKitFrame: screen.frame,
            primaryScreenTop: NSScreen.screens.first?.frame.maxY ?? 0)
        content.configure(scope: prefs.windowScope, grouped: prefs.groupByApplication, screenRect: screenRect)
        thumbnails.begin(items: items)
        content.setItems(items)

        // 菜单栏应用的激活行为存在系统差异，结合应用激活和窗口置前确保可见。
        let activated = NSRunningApplication.current.activate()
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeFirstResponder(content)
        isVisible = true
        DebugLog.write("display: activate=\(activated) appActive=\(NSApp.isActive) winVisible=\(window.isVisible) winScreen=\(window.screen?.frame.debugDescription ?? "nil") occlusion=\(window.occlusionState.rawValue)")

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, generation == self.generation else { return }
            window.makeKey()
            let frOK = window.makeFirstResponder(content)
            DebugLog.write("display(async): appActive=\(NSApp.isActive) key=\(window.isKeyWindow) frOK=\(frOK) winVisible=\(window.isVisible)")
        }

        // 打开后仅检查一次窗口服务器状态，辅助诊断可见性；不是周期轮询。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.isVisible else { return }
            let wid = CGWindowID(window.windowNumber)
            let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]]
            let onscreen = (info?.first?[kCGWindowIsOnscreen as String] as? Bool) ?? false
            DebugLog.write("CG check: onscreen=\(onscreen) appActive=\(NSApp.isActive) key=\(window.isKeyWindow)")
        }

        content.layoutSubtreeIfNeeded()
        thumbnails.request(indices: content.visibleSourceIndices)
    }

    func hide() {
        // 已关闭时不再递增操作版本，避免失焦通知撤销稍后执行的窗口聚焦。
        guard isVisible || isLoading else { return }
        DebugLog.write("hide called (isVisible=\(isVisible))")
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        thumbnails.reset()
        generation += 1
        isVisible = false
        window?.orderOut(nil)
        content?.setItems([])
    }

    // MARK: - 加载和错误提示

    private func presentPermissionAlert() {
        guard !isPresentingAlert else { return }
        isPresentingAlert = true
        defer { isPresentingAlert = false }
        let alert = NSAlert()
        alert.messageText = "需要「屏幕录制」权限"
        alert.informativeText = """
        任务视图需要「屏幕录制」权限来读取窗口列表和生成缩略图。\
        请在系统设置中允许 TaskView，然后从菜单栏退出并重新打开本应用。\n\
        当前应用：\(Bundle.main.bundlePath)\n\
        若已经允许，请移除旧条目后添加这个路径的应用。开发版重建后可能需要重新授权。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openScreenRecordingSettings()
        }
    }

    private func presentLoadError(_ error: Error) {
        guard !isPresentingAlert else { return }
        isPresentingAlert = true
        defer { isPresentingAlert = false }
        let alert = NSAlert()
        alert.messageText = "无法读取窗口列表"
        alert.informativeText = "请稍后重试。\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - 窗口选择回调

    private func closeSelected(_ index: Int) {
        guard !isClosingWindow, isVisible, let item = content?.items[safe: index] else { return }
        let target = WindowCloseTarget(pid: item.pid, title: item.originalTitle, frame: item.frame)
        hide()
        let gen = generation
        guard Permissions.isAccessibilityTrusted else {
            presentWindowCloseError(.permissionRequired)
            return
        }
        isClosingWindow = true
        Task { @MainActor [weak self] in
            // 先撤下覆盖层，让目标应用自己的保存确认可以显示出来。
            try? await Task.sleep(nanoseconds: 50_000_000)
            NSRunningApplication(processIdentifier: target.pid)?.activate()
            // 辅助功能通信可能等待目标应用响应，不能阻塞主线程。
            let error = await Task.detached(priority: .userInitiated) { () -> WindowCloseError? in
                do {
                    try WindowCloseService.close(target, using: AXWindowCloseBackend())
                    return nil
                } catch {
                    return error as? WindowCloseError ?? .system(AXError.failure.rawValue)
                }
            }.value
            guard let self else { return }
            self.isClosingWindow = false
            guard let error, self.generation == gen else { return }
            self.presentWindowCloseError(error)
        }
    }

    private func presentWindowCloseError(_ error: WindowCloseError) {
        guard !isPresentingAlert else { return }
        isPresentingAlert = true
        defer { isPresentingAlert = false }
        let alert = NSAlert()
        alert.messageText = "无法关闭窗口"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        if error == .permissionRequired {
            alert.addButton(withTitle: "打开辅助功能设置")
            alert.addButton(withTitle: "取消")
        } else { alert.addButton(withTitle: "确定") }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if error == .permissionRequired, response == .alertFirstButtonReturn {
            Permissions.openAccessibilitySettings()
        }
    }

    private func focusSelected(_ index: Int) {
        guard let item = content?.items[safe: index] else { return }
        let wasVisible = isVisible
        hide()
        guard wasVisible else { return }
        let gen = generation
        // 稍后再激活目标，给系统时间撤下覆盖层的键盘焦点。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.generation == gen else { return }
            FocusController.focus(item)
        }
    }

    // MARK: - 窗口配置

    private func buildWindowIfNeeded() {
        guard window == nil else { return }

        let overlay = OverlayWindow(contentRect: .zero,
                                    styleMask: .borderless,
                                    backing: .buffered,
                                    defer: false)
        overlay.isReleasedWhenClosed = false
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        // 跟随当前桌面空间；仅设置加入所有空间时，未激活的菜单栏应用可能仍不可见。
        overlay.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        overlay.isMovable = false
        // 切换到其他应用时隐藏覆盖层，允许用户操作系统权限设置。
        overlay.hidesOnDeactivate = true
        overlay.acceptsMouseMovedEvents = true
        overlay.isRestorable = false

        let effect = NSVisualEffectView()
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active

        // 在系统模糊效果上叠加压暗层，提高窗口卡片和文字的对比度。
        let dimming = NSView()
        dimming.wantsLayer = true
        dimming.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        effect.addSubview(dimming)

        let content = OverlayContentView()
        effect.addSubview(content)
        overlay.contentView = effect

        dimming.frame = effect.bounds
        dimming.autoresizingMask = [.width, .height]
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]

        content.onFocusSelected = { [weak self] index in self?.focusSelected(index) }
        content.onCloseRequested = { [weak self] in self?.hide() }
        content.onCloseWindow = { [weak self] index in self?.closeSelected(index) }
        content.onVisibleIndicesChanged = { [weak self] indices in
            guard let self, self.isVisible else { return }
            self.thumbnails.request(indices: indices)
        }
        content.onScopeChanged = { AppSettings.shared.preferences.windowScope = $0 }
        content.onGroupingChanged = { AppSettings.shared.preferences.groupByApplication = $0 }
        thumbnails.onImageChanged = { [weak self] index, image in
            guard let self, self.isVisible else { return }
            self.content?.setThumbnail(image, at: index)
        }
        overlay.onKeyDown = { event in
            content.keyDown(with: event)
        }

        self.window = overlay
        self.content = content
        self.dimming = dimming
    }

    private func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

private extension Array where Element == WindowItem {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
