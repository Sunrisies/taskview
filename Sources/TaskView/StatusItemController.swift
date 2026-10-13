import AppKit

/// 菜单栏入口，提供任务视图、设置、权限跳转和退出菜单。
@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private let onShow: () -> Void
    private let onQuit: () -> Void
    private let onSettings: () -> Void
    private let buildInfo = AppBuildInfo.current

    init(onShow: @escaping () -> Void, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onShow = onShow
        self.onSettings = onSettings
        self.onQuit = onQuit
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "rectangle.stack.fill",
                                accessibilityDescription: "任务视图")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "任务视图（\(AppSettings.shared.preferences.shortcut.displayName)）"
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "打开任务视图",
                                  action: #selector(showTaskView),
                                  keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let screenItem = NSMenuItem(title: "屏幕录制权限…",
                                    action: #selector(openScreenSettings),
                                    keyEquivalent: "")
        screenItem.target = self
        menu.addItem(screenItem)

        let axItem = NSMenuItem(title: "辅助功能权限…",
                                action: #selector(openAccessibilitySettings),
                                keyEquivalent: "")
        axItem.target = self
        menu.addItem(axItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "关于任务视图…", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "退出任务视图",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func showTaskView() {
        onShow()
    }

    func updateShortcut(_ shortcut: Shortcut) {
        statusItem?.button?.toolTip = "任务视图（\(shortcut.displayName)）"
    }

    @objc private func openSettings() { onSettings() }

    @objc private func openScreenSettings() {
        Permissions.openScreenRecordingSettings()
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func quit() {
        onQuit()
    }

    @objc private func showAbout() {
        // 显示本进程的信息；复制后可直接用于反馈问题。
        let alert = NSAlert()
        alert.messageText = "任务视图 TaskView"
        alert.informativeText = buildInfo.details
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "复制信息")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(buildInfo.details, forType: .string)
        }
    }
}
