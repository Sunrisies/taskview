import AppKit
import Carbon.HIToolbox

// 实例化原生控件并执行动作，测试注册服务不会占用真实系统快捷键。

enum DebugLog { static func write(_ message: String) {} }

@main
struct SettingsUITests {
    @MainActor
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let backend = FakeHotKeyBackend()
        precondition(GlobalHotKey.failureDescription(OSStatus(eventHotKeyExistsErr)).contains("占用"))
        precondition(GlobalHotKey.failureDescription(OSStatus(eventInternalErr)).contains("系统快捷键服务"))
        let modifiers = UInt32(controlKey | optionKey | cmdKey | shiftKey)
        let hotKey = GlobalHotKey(backend: backend)
        precondition(hotKey.register(keyCode: 79, modifiers: modifiers) == noErr)
        let blockerID = EventHotKeyID(signature: 0x5445_5354, id: 1)
        let (blockedStatus, blocker) = backend.register(keyCode: 80, modifiers: modifiers, id: blockerID)
        precondition(blockedStatus == noErr)
        precondition(hotKey.register(keyCode: 80, modifiers: modifiers) != noErr)
        precondition(backend.keys.contains(79), "Conflict must preserve old shortcut")
        backend.unregister(blocker!)
        precondition(hotKey.register(keyCode: 80, modifiers: modifiers) == noErr)
        precondition(!backend.keys.contains(79) && backend.keys.contains(80))
        hotKey.unregister()
        precondition(backend.keys.isEmpty)
        let settings = AppSettings(store: MemoryPreferences())
        let service = FakeLoginService()
        let login = LoginItemController(service: service)
        var recordingChanges: [Bool] = []
        let controller = SettingsWindowController(settings: settings, loginItems: login,
            onShortcut: { shortcut in
                guard shortcut.isValid else { return "无效的快捷键" }
                settings.preferences.shortcut = shortcut
                return nil
            }, onRecordingChanged: { recordingChanges.append($0) })
        guard let window = controller.window, let content = window.contentView else { fatalError("Missing settings window") }
        window.layoutIfNeeded()
        content.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(content)
        let buttons = views.compactMap { $0 as? NSButton }
        guard let recorder = buttons.compactMap({ $0 as? ShortcutRecorderButton }).first,
              let launchToggle = buttons.first(where: { $0.title == "开机自启（登录后启动）" }),
              let hoverToggle = buttons.first(where: { $0.title == "鼠标悬停时选中窗口" }),
              let slider = views.compactMap({ $0 as? NSSlider }).first,
              let picker = views.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.itemTitles.contains("标准（960）") }),
              let scopePicker = views.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.itemTitles.contains("当前显示器") }),
              let groupingToggle = buttons.first(where: { $0.title == "默认按应用分组" }) else { fatalError("Missing settings controls") }
        precondition(recorder.title == "⌥Tab" && launchToggle.state == .off)
        launchToggle.performClick(nil)
        precondition(service.registrations == 1 && login.isRequested && launchToggle.state == .on)
        launchToggle.performClick(nil)
        precondition(service.removals == 1 && !login.isRequested)
        hoverToggle.performClick(nil)
        precondition(!settings.preferences.hoverSelection)
        slider.doubleValue = 0.4
        app.sendAction(slider.action!, to: slider.target, from: slider)
        precondition(settings.preferences.backgroundOpacity == 0.4)
        picker.selectItem(at: 2)
        app.sendAction(picker.action!, to: picker.target, from: picker)
        precondition(settings.preferences.thumbnailPixels == 1440)
        scopePicker.selectItem(at: 1)
        app.sendAction(scopePicker.action!, to: scopePicker.target, from: scopePicker)
        groupingToggle.performClick(nil)
        precondition(settings.preferences.windowScope == .currentDisplay && settings.preferences.groupByApplication)
        recorder.beginRecording()
        precondition(recorder.isRecording && recordingChanges.last == true)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "t",
            charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17)!
        recorder.keyDown(with: event)
        precondition(!recorder.isRecording && recorder.title == "⌃⌥T" && settings.preferences.shortcut.keyCode == 17)
        precondition(recordingChanges == [true, false])
        recorder.beginRecording()
        let invalid = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "t",
            charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17)!
        recorder.keyDown(with: invalid)
        precondition(recorder.isRecording && settings.preferences.shortcut.keyCode == 17)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        precondition(!recorder.isRecording && recordingChanges.last == false)
        controller.showShortcutError(nil)
        let reset = buttons.first { $0.title == "恢复默认快捷键（⌥Tab）" }!
        reset.performClick(nil)
        precondition(settings.preferences.shortcut == .default && recorder.title == "⌥Tab")
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        window.layoutIfNeeded()
        content.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        for view in views where !view.isHidden {
            precondition(!view.hasAmbiguousLayout, "Ambiguous layout: \(type(of: view))")
        }
        if let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: image)
            if let png = image.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: "build/tests/settings-preview.png"))
            }
        }
        print("PASS: hotkey conflict/replacement with test backend, settings window, shortcut recording/cancel/reset, login toggle, appearance controls, layout")
        window.orderOut(nil)
    }
}

final class FakeHotKeyBackend: HotKeyBackend {
    var references: [EventHotKeyRef: UInt32] = [:]
    var nextReference = 1
    var keys: Set<UInt32> { Set(references.values) }
    func register(keyCode: UInt32, modifiers: UInt32, id: EventHotKeyID) -> (OSStatus, EventHotKeyRef?) {
        if keys.contains(keyCode) { return (OSStatus(eventHotKeyExistsErr), nil) }
        let reference = OpaquePointer(bitPattern: nextReference)!
        nextReference += 1
        references[reference] = keyCode
        return (noErr, reference)
    }
    func unregister(_ reference: EventHotKeyRef) { references.removeValue(forKey: reference) }
}
