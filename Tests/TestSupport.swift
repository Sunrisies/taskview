import AppKit
import ServiceManagement

// 内存存储和可控制的登录项服务，让测试不依赖用户的偏好和系统自启状态。

final class MemoryPreferences: PreferencesStore {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value as? Data }
}
final class FakeLoginService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var nextStatus: SMAppService.Status = .enabled
    var shouldFail = false
    var registrations = 0
    var removals = 0
    func register() throws {
        registrations += 1
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        status = nextStatus
    }
    func unregister() throws {
        removals += 1
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        status = .notRegistered
    }
}
