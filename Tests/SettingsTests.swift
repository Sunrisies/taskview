import AppKit
import Carbon.HIToolbox
import ServiceManagement
import ScreenCaptureKit

// 验证权限分类、偏好数据、自启状态机和窗口匹配，系统修改使用替代服务。

@main
struct SettingsTests {
    @MainActor
    static func main() throws {
        let denied = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        let serviceError = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.internalError.rawValue)
        let unrelated = NSError(domain: "OtherService", code: SCStreamError.Code.userDeclined.rawValue)
        precondition(Permissions.isScreenCaptureDenied(denied))
        precondition(!Permissions.isScreenCaptureDenied(serviceError))
        precondition(!Permissions.isScreenCaptureDenied(unrelated))
        Permissions.recordScreenCaptureSuccess()
        precondition(Permissions.isScreenRecordingTrusted)
        Permissions.recordScreenCaptureFailure(serviceError)
        precondition(Permissions.isScreenRecordingTrusted, "Service failure must not overwrite an established grant")
        Permissions.recordScreenCaptureFailure(denied)
        precondition(!Permissions.isScreenRecordingTrusted)
        let store = MemoryPreferences()
        let settings = AppSettings(store: store)
        precondition(settings.preferences == AppPreferences())
        let binding = Shortcut(keyCode: 17, modifiers: UInt32(controlKey | optionKey), keyName: "T")
        precondition(binding.isValid && binding.displayName == "⌃⌥T")
        precondition(!Shortcut(keyCode: 17, modifiers: 0, keyName: "T").isValid)
        precondition(!Shortcut(keyCode: 56, modifiers: UInt32(optionKey), keyName: "Shift").isValid)
        precondition(!Shortcut(keyCode: 48, modifiers: UInt32(cmdKey), keyName: "Tab").isValid)
        precondition(!Shortcut(keyCode: 17, modifiers: UInt32(optionKey) | (1 << 30), keyName: "T").isValid)
        settings.preferences.shortcut = binding
        settings.preferences.hoverSelection = false
        settings.preferences.backgroundOpacity = 0.42
        settings.preferences.thumbnailPixels = 1440
        settings.preferences.windowScope = .currentDisplay
        settings.preferences.groupByApplication = true
        let reloaded = AppSettings(store: store)
        precondition(reloaded.preferences == settings.preferences, "All parameters must survive reload")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings.preferences)) as! [String: Any]
        legacy.removeValue(forKey: "windowScope")
        legacy.removeValue(forKey: "groupByApplication")
        store.set(try JSONSerialization.data(withJSONObject: legacy), forKey: AppSettings.storageKey)
        let migrated = AppSettings(store: store).preferences
        precondition(migrated.shortcut == binding && migrated.backgroundOpacity == 0.42 && !migrated.hoverSelection)
        precondition(migrated.windowScope == .allDisplays && !migrated.groupByApplication)
        var invalid = AppPreferences()
        invalid.shortcut.modifiers = 0
        invalid.backgroundOpacity = 3
        invalid.thumbnailPixels = -1
        store.set(try JSONEncoder().encode(invalid), forKey: AppSettings.storageKey)
        let repaired = AppSettings(store: store).preferences
        precondition(repaired.shortcut == .default && repaired.backgroundOpacity == 0.9 && repaired.thumbnailPixels == 960)
        store.set(Data("bad json".utf8), forKey: AppSettings.storageKey)
        precondition(AppSettings(store: store).preferences == AppPreferences())

        let service = FakeLoginService()
        let login = LoginItemController(service: service)
        precondition(!login.isRequested)
        login.setEnabled(true)
        precondition(login.status == .enabled && login.isRequested && service.registrations == 1)
        login.setEnabled(true)
        precondition(service.registrations == 1, "Already enabled must not register again")
        login.setEnabled(false)
        precondition(!login.isRequested && service.removals == 1)
        service.nextStatus = .requiresApproval
        login.setEnabled(true)
        precondition(login.isRequested && login.status == .requiresApproval)
        login.setEnabled(false)
        service.shouldFail = true
        login.setEnabled(true)
        precondition(!login.isRequested && login.errorMessage != nil, "Failure must not pretend enabled")
        service.shouldFail = false
        service.status = .enabled
        login.refresh()
        precondition(login.isRequested, "External system changes must refresh")
        service.shouldFail = true
        login.setEnabled(false)
        precondition(login.isRequested && login.errorMessage != nil, "Failed removal must retain system status")

        let frame = CGRect(x: 20, y: 40, width: 800, height: 600)
        let elsewhere = CGRect(x: 900, y: 40, width: 800, height: 600)
        let candidates = [WindowMatcher.Candidate(title: "Document", frame: elsewhere),
                          WindowMatcher.Candidate(title: "Document", frame: frame)]
        precondition(WindowMatcher.bestIndex(candidates: candidates, title: "Document", frame: frame) == 1)
        precondition(WindowMatcher.bestIndex(candidates: [candidates[1], candidates[1]], title: "Document", frame: frame) == nil)
        precondition(WindowMatcher.bestIndex(candidates: [.init(title: nil, frame: frame)], title: nil, frame: frame) == 0)
        precondition(WindowMatcher.bestIndex(candidates: [.init(title: "Doc", frame: elsewhere)], title: "Document", frame: frame) == nil)
        precondition(WindowMatcher.bestIndex(candidates: [.init(title: "New title", frame: frame)], title: "Old title", frame: frame) == 0)
        print("PASS: permission classification/state, settings persistence, validation, login enable/disable/approval/errors, window matching")
    }
}
