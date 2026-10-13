import ServiceManagement
import Combine

/// 系统登录项服务的可替代接口，测试时不改动真实自启状态。
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}
extension SMAppService: LoginItemService {}

@MainActor
final class LoginItemController: ObservableObject {
    private let service: LoginItemService
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?

    init(service: LoginItemService = SMAppService.mainApp) {
        self.service = service
        refresh()
    }

    var isRequested: Bool { status == .enabled || status == .requiresApproval }
    var statusText: String {
        switch status {
        case .enabled: return "已开启，下次登录时启动"
        case .requiresApproval: return "等待系统批准，请在「登录项」中允许"
        case .notRegistered: return "未开启"
        case .notFound: return "系统未找到应用，请从完整的 TaskView.app 运行"
        @unknown default: return "无法确定状态，请查看系统登录项"
        }
    }

    func refresh() { status = service.status }
    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        refresh()
        guard enabled != isRequested else { return }
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            errorMessage = "无法更新开机自启：\(error.localizedDescription)"
        }
        refresh()
    }
}
