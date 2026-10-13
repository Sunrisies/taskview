import AppKit
import ServiceManagement

/// 原生设置窗口，负责控件交互、快捷键录制和权限状态刷新。
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let loginItems: LoginItemController
    private let settings: AppSettings
    private let onShortcut: (Shortcut) -> String?
    private let recorder = ShortcutRecorderButton()
    private let shortcutError = NSTextField(wrappingLabelWithString: "")
    private let loginToggle = NSButton(checkboxWithTitle: "开机自启（登录后启动）", target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let loginError = NSTextField(wrappingLabelWithString: "")
    private let hoverToggle = NSButton(checkboxWithTitle: "鼠标悬停时选中窗口", target: nil, action: nil)
    private let opacitySlider = NSSlider(value: 0.65, minValue: 0.2, maxValue: 0.9, target: nil, action: nil)
    private let opacityLabel = NSTextField(labelWithString: "65%")
    private let qualityPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let scopePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let groupingToggle = NSButton(checkboxWithTitle: "默认按应用分组", target: nil, action: nil)
    private let screenStatus = NSTextField(labelWithString: "")
    private let accessibilityStatus = NSTextField(labelWithString: "")
    private let permissionCheckStatus = NSTextField(wrappingLabelWithString: "")
    private var isCheckingPermissions = false
    private var activeObserver: NSObjectProtocol?

    init(settings: AppSettings, loginItems: LoginItemController,
         onShortcut: @escaping (Shortcut) -> String?, onRecordingChanged: @escaping (Bool) -> Void) {
        self.settings = settings
        self.loginItems = loginItems
        self.onShortcut = onShortcut
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "任务视图设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        recorder.onRecordingChanged = onRecordingChanged
        recorder.onShortcut = { [weak self] shortcut in
            guard let self else { return false }
            let error = self.onShortcut(shortcut)
            self.showShortcutError(error)
            self.recorder.shortcut = self.settings.preferences.shortcut
            return error == nil
        }
        buildContent(in: window)
        refresh()
        window.center()
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) } }

    func show() {
        refresh()
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowDidResignKey(_ notification: Notification) { recorder.stopRecording() }
    func windowWillClose(_ notification: Notification) { recorder.stopRecording() }
    func showShortcutError(_ error: String?) {
        shortcutError.stringValue = error ?? ""
        shortcutError.isHidden = error == nil
    }

    private func buildContent(in window: NSWindow) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor
        window.contentView = scroll
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])

        func add(_ view: NSView) {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        func heading(_ title: String) {
            if !stack.arrangedSubviews.isEmpty {
                let separator = NSBox(); separator.boxType = .separator; add(separator)
            }
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            add(label)
        }
        func hint(_ text: String) {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            add(label)
        }
        func button(_ title: String, _ action: Selector) -> NSButton {
            NSButton(title: title, target: self, action: action)
        }
        func row(_ views: [NSView]) -> NSStackView {
            for view in views where type(of: view) == NSView.self {
                view.heightAnchor.constraint(equalToConstant: 1).isActive = true
            }
            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12
            return row
        }

        heading("快捷键")
        recorder.bezelStyle = .rounded
        recorder.target = recorder
        recorder.action = #selector(ShortcutRecorderButton.beginRecording)
        recorder.widthAnchor.constraint(equalToConstant: 190).isActive = true
        add(row([NSTextField(labelWithString: "打开 / 关闭任务视图"), NSView(), recorder]))
        hint("点击快捷键后按下新组合；需包含 ⌘、⌥ 或 ⌃，Esc 取消。")
        shortcutError.textColor = .systemRed
        shortcutError.font = .systemFont(ofSize: 11)
        add(shortcutError)
        add(row([button("恢复默认快捷键（⌥Tab）", #selector(resetShortcut)), NSView()]))

        heading("启动")
        loginToggle.target = self; loginToggle.action = #selector(changeLoginItem)
        add(loginToggle)
        loginStatus.font = .systemFont(ofSize: 11); loginStatus.textColor = .secondaryLabelColor
        add(loginStatus)
        loginError.font = .systemFont(ofSize: 11); loginError.textColor = .systemRed
        add(loginError)
        add(row([button("打开系统登录项设置…", #selector(openLoginSettings)), NSView()]))

        heading("显示与操作")
        scopePicker.addItems(withTitles: ["所有显示器", "当前显示器"])
        scopePicker.target = self; scopePicker.action = #selector(changeScope)
        add(row([NSTextField(labelWithString: "窗口范围"), scopePicker, NSView()]))
        groupingToggle.target = self; groupingToggle.action = #selector(changeGrouping)
        add(groupingToggle)
        hoverToggle.target = self; hoverToggle.action = #selector(changeHover)
        add(hoverToggle)
        opacitySlider.target = self; opacitySlider.action = #selector(changeOpacity)
        opacitySlider.isContinuous = true
        opacityLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        opacityLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        add(row([NSTextField(labelWithString: "背景压暗"), opacitySlider, opacityLabel]))
        qualityPicker.addItems(withTitles: ["省资源（480）", "标准（960）", "高清（1440）"])
        qualityPicker.target = self; qualityPicker.action = #selector(changeQuality)
        add(row([NSTextField(labelWithString: "缩略图清晰度"), qualityPicker, NSView()]))
        hint("设置自动保存；显示参数在下次打开任务视图时生效。")

        heading("系统权限")
        add(row([screenStatus, NSView(), button("设置…", #selector(openScreenSettings))]))
        add(row([accessibilityStatus, NSView(), button("设置…", #selector(openAccessibilitySettings))]))
        add(row([button("重新检查权限", #selector(checkPermissions)), NSView()]))
        permissionCheckStatus.font = .systemFont(ofSize: 11)
        permissionCheckStatus.textColor = .secondaryLabelColor
        add(permissionCheckStatus)
        hint("当前应用：\(Bundle.main.bundlePath)")
        hint("屏幕录制用于窗口截图，辅助功能用于精确聚焦。授权后可能需重启应用。")
    }

    private func refresh() {
        loginItems.refresh()
        loginToggle.state = loginItems.isRequested ? .on : .off
        loginStatus.stringValue = loginItems.statusText
        loginError.stringValue = loginItems.errorMessage ?? ""
        loginError.isHidden = loginItems.errorMessage == nil
        recorder.shortcut = settings.preferences.shortcut
        if !recorder.isRecording { recorder.title = recorder.shortcut.displayName }
        hoverToggle.state = settings.preferences.hoverSelection ? .on : .off
        opacitySlider.doubleValue = settings.preferences.backgroundOpacity
        opacityLabel.stringValue = "\(Int(opacitySlider.doubleValue * 100))%"
        qualityPicker.selectItem(at: [480, 960, 1440].firstIndex(of: settings.preferences.thumbnailPixels) ?? 1)
        scopePicker.selectItem(at: settings.preferences.windowScope == .allDisplays ? 0 : 1)
        groupingToggle.state = settings.preferences.groupByApplication ? .on : .off
        screenStatus.stringValue = "屏幕录制：\(Permissions.isScreenRecordingTrusted ? "已授权" : "未授权")"
        accessibilityStatus.stringValue = "辅助功能：\(Permissions.isAccessibilityTrusted ? "已授权" : "未授权")"
    }

    @objc private func resetShortcut() {
        recorder.stopRecording()
        showShortcutError(onShortcut(.default))
        refresh()
    }
    @objc private func changeLoginItem() {
        loginItems.setEnabled(loginToggle.state == .on)
        refresh()
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func changeHover() { settings.preferences.hoverSelection = hoverToggle.state == .on }
    @objc private func changeOpacity() {
        settings.preferences.backgroundOpacity = opacitySlider.doubleValue
        opacityLabel.stringValue = "\(Int(opacitySlider.doubleValue * 100))%"
    }
    @objc private func changeQuality() {
        settings.preferences.thumbnailPixels = [480, 960, 1440][qualityPicker.indexOfSelectedItem]
    }
    @objc private func changeScope() {
        settings.preferences.windowScope = scopePicker.indexOfSelectedItem == 0 ? .allDisplays : .currentDisplay
    }
    @objc private func changeGrouping() {
        settings.preferences.groupByApplication = groupingToggle.state == .on
    }
    @objc private func openScreenSettings() { Permissions.openScreenRecordingSettings() }
    @objc private func openAccessibilitySettings() { Permissions.openAccessibilitySettings() }
    @objc private func checkPermissions() {
        guard !isCheckingPermissions else { return }
        isCheckingPermissions = true
        permissionCheckStatus.stringValue = "正在通过窗口读取接口检查…"
        Task { @MainActor [weak self] in
            let error = await Permissions.verifyScreenRecordingAccess()
            guard let self else { return }
            self.isCheckingPermissions = false
            self.permissionCheckStatus.stringValue = error ?? "窗口读取成功，屏幕录制权限可用。"
            self.refresh()
        }
    }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: Shortcut = .default
    var onShortcut: ((Shortcut) -> Bool)?
    var onRecordingChanged: ((Bool) -> Void)?
    private(set) var isRecording = false
    override var acceptsFirstResponder: Bool { true }

    @objc func beginRecording() {
        guard !isRecording else { return }
        guard window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        title = "请按下快捷键…"
        onRecordingChanged?(true)
    }
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        title = shortcut.displayName
        onRecordingChanged?(false)
    }
    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { stopRecording(); return }
        if onShortcut?(Shortcut(event: event)) == true { stopRecording() }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }
}
