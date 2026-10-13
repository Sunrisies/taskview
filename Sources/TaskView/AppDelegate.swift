import AppKit

/// 应用生命周期入口，连接菜单栏、快捷键、权限引导和设置窗口。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private let hotKey = GlobalHotKey()
    private var statusController: StatusItemController?
    private var settingsController: SettingsWindowController?
    private let settings = AppSettings.shared
    private var isRecordingShortcut = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("launched pid=\(getpid())")
        DebugLog.write("app path=\(Bundle.main.bundlePath) executable=\(Bundle.main.executablePath ?? "unknown")")

        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in
            DebugLog.write("app didBecomeActive")
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            DebugLog.write("app didResignActive")
            MainActor.assumeIsolated {
                self?.overlay.hide()
            }
        }

        hotKey.onTrigger = { [weak self] in
            guard let self, !self.isRecordingShortcut else { return }
            DebugLog.write("toggle requested (visible=\(self.overlay.isVisible))")
            self.overlay.toggle()
        }
        let shortcut = settings.preferences.shortcut
        let hotKeyStatus = hotKey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)

        let status = StatusItemController(
            onShow: { [weak self] in self?.overlay.show() },
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        status.install()
        statusController = status

        if hotKeyStatus != noErr {
            let alert = NSAlert()
            alert.messageText = "无法注册 \(shortcut.displayName) 快捷键"
            alert.informativeText = GlobalHotKey.failureDescription(hotKeyStatus) + "可从菜单栏打开设置，修改快捷键。"
            alert.addButton(withTitle: "确定")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }

        // 只在首次启动请求权限，避免拒绝后每次登录都重复提示。
        if !UserDefaults.standard.bool(forKey: "taskview.hasShownPermissionSetup") {
            UserDefaults.standard.set(true, forKey: "taskview.hasShownPermissionSetup")
            if !Permissions.isScreenRecordingTrusted {
                Permissions.requestScreenRecordingAccess()
            }
            if !Permissions.isAccessibilityTrusted {
                Permissions.requestAccessibilityAccess()
            }
        }

        // 手动调试入口：按启动参数打开设置或任务视图。
        if CommandLine.arguments.contains("--settings") {
            showSettings()
        } else if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.overlay.show()
            }
        }

    }

    private func showSettings() {
        overlay.hide()
        if settingsController == nil {
            settingsController = SettingsWindowController(settings: settings, loginItems: LoginItemController(),
                onShortcut: { [weak self] shortcut in self?.applyShortcut(shortcut) ?? "应用正在退出" },
                onRecordingChanged: { [weak self] recording in
                    guard let self else { return }
                    self.isRecordingShortcut = recording
                    if recording {
                        self.hotKey.unregister()
                    } else {
                        let shortcut = self.settings.preferences.shortcut
                        let result = self.hotKey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
                        if result != noErr {
                            self.settingsController?.showShortcutError(GlobalHotKey.failureDescription(result))
                        }
                    }
                })
        }
        settingsController?.show()
    }

    private func applyShortcut(_ shortcut: Shortcut) -> String? {
        guard shortcut.isValid else { return "请选择包含 ⌘、⌥ 或 ⌃ 的组合，不能使用单独的修饰键或 ⌘Tab。" }
        let result = hotKey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
        guard result == noErr else { return GlobalHotKey.failureDescription(result) + "未保存修改。" }
        settings.preferences.shortcut = shortcut
        statusController?.updateShortcut(shortcut)
        return nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.hide()
        hotKey.unregister()
    }
}
