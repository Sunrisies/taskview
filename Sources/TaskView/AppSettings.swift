import AppKit
import Carbon.HIToolbox
import Combine

/// 可保存的快捷键数据：键位使用硬件键码，显示名称用于设置界面。
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyName: String

    static let `default` = Shortcut(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey), keyName: "Tab")
    static let allowedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    var isValid: Bool {
        keyCode < 128 && ![53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
            && modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
            && modifiers & ~Self.allowedModifiers == 0 && !keyName.isEmpty && keyName.count <= 24
            && !(keyCode == UInt32(kVK_Tab) && modifiers == UInt32(cmdKey))
    }

    var displayName: String {
        [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"),
         (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
            .filter { modifiers & $0.0 != 0 }.map { $0.1 }.joined() + keyName
    }

    init(keyCode: UInt32, modifiers: UInt32, keyName: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyName = keyName
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var mask: UInt32 = 0
        if event.modifierFlags.contains(.command) { mask |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { mask |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { mask |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { mask |= UInt32(shiftKey) }
        modifiers = mask
        let names: [UInt16: String] = [48: "Tab", 49: "Space", 36: "Return", 76: "Enter",
            51: "Delete", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down"]
        keyName = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
    }
}

enum WindowScope: String, Codable {
    case allDisplays
    case currentDisplay
}

struct AppPreferences: Codable, Equatable {
    /// 界面设置集中保存；登录自启由系统管理，不在这里存一个容易过期的开关。
    var shortcut: Shortcut = .default
    var hoverSelection = true
    var backgroundOpacity = 0.65
    var thumbnailPixels = 960
    var windowScope: WindowScope = .allDisplays
    var groupByApplication = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case shortcut, hoverSelection, backgroundOpacity, thumbnailPixels, windowScope, groupByApplication
    }

    /// 新增字段缺失时使用默认值，保留旧版本已保存的快捷键和显示参数。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        shortcut = try values.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? .default
        hoverSelection = try values.decodeIfPresent(Bool.self, forKey: .hoverSelection) ?? true
        backgroundOpacity = try values.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.65
        thumbnailPixels = try values.decodeIfPresent(Int.self, forKey: .thumbnailPixels) ?? 960
        let scope = try values.decodeIfPresent(String.self, forKey: .windowScope)
        windowScope = scope.flatMap(WindowScope.init(rawValue:)) ?? .allDisplays
        groupByApplication = try values.decodeIfPresent(Bool.self, forKey: .groupByApplication) ?? false
    }

    var normalized: Self {
        // 修复被手工修改或旧版本写入的非法值，避免异常尺寸和无效快捷键。
        var value = self
        if !shortcut.isValid { value.shortcut = .default }
        value.backgroundOpacity = backgroundOpacity.isFinite ? min(max(backgroundOpacity, 0.2), 0.9) : 0.65
        if ![480, 960, 1440].contains(thumbnailPixels) { value.thumbnailPixels = 960 }
        return value
    }
}

protocol PreferencesStore {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}
extension UserDefaults: PreferencesStore {}

@MainActor
final class AppSettings: ObservableObject {
    /// 只在设置发生变化时持久化，不安排后台轮询。
    static let storageKey = "taskview.preferences.v1"
    static let shared = AppSettings()
    private let store: PreferencesStore
    @Published var preferences: AppPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences.normalized) {
                store.set(data, forKey: Self.storageKey)
            }
        }
    }

    init(store: PreferencesStore = UserDefaults.standard) {
        self.store = store
        preferences = store.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }?.normalized ?? AppPreferences()
    }
}
