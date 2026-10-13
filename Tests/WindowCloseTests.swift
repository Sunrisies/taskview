import AppKit
import ApplicationServices

/// 替代关闭服务记录操作，不关闭用户机器中的窗口。
private final class CloseBackend: WindowCloseBackend {
    var isTrusted = true
    var values: [AccessibleWindow<Int>] = []
    var closed: [Int] = []
    var readCount = 0
    var failure: WindowCloseError?
    func windows(pid: pid_t) throws -> [AccessibleWindow<Int>] { readCount += 1; return values }
    func pressCloseButton(window: Int) throws {
        if let failure { throw failure }
        closed.append(window)
    }
}

@main
struct WindowCloseTests {
    static func main() throws {
        let frame = CGRect(x: 10, y: 20, width: 800, height: 600)
        let target = WindowCloseTarget(pid: 1, title: "Document", frame: frame)
        let backend = CloseBackend()
        func candidate(_ id: Int, _ title: String?, _ rect: CGRect) -> AccessibleWindow<Int> {
            AccessibleWindow(element: id, metadata: .init(title: title, frame: rect))
        }
        // 每个错误分支都必须在动作完成前返回。
        func fails(_ expected: WindowCloseError) {
            let before = backend.closed
            do { try WindowCloseService.close(target, using: backend); preconditionFailure("应拒绝关闭") }
            catch { precondition((error as? WindowCloseError) == expected) }
            precondition(before == backend.closed)
        }
        backend.isTrusted = false
        fails(.permissionRequired)
        precondition(backend.readCount == 0)
        backend.isTrusted = true
        backend.values = [candidate(1, "Document", frame), candidate(2, "Document", CGRect(x: 900, y: 20, width: 800, height: 600))]
        try WindowCloseService.close(target, using: backend)
        precondition(backend.closed == [1])
        backend.values = [candidate(1, "Document", frame), candidate(2, "Document", frame)]
        fails(.windowChanged)
        backend.values = [candidate(1, "Doc", frame)]
        fails(.windowChanged)
        backend.values = [candidate(1, "Different", frame)]
        fails(.windowChanged)
        backend.values = [candidate(1, "Document", CGRect(x: 100, y: 20, width: 800, height: 600))]
        fails(.windowChanged)
        backend.values = []
        fails(.windowChanged)
        backend.values = [candidate(1, "Document", frame)]
        for error in [WindowCloseError.unsupported, .disabled, .system(AXError.cannotComplete.rawValue)] {
            backend.failure = error
            fails(error)
        }
        backend.failure = nil
        let untitled = WindowCloseTarget(pid: 1, title: nil, frame: frame)
        backend.values = [candidate(3, nil, frame)]
        try WindowCloseService.close(untitled, using: backend)
        precondition(backend.closed.last == 3)
        var point = CGPoint(x: 10, y: 20)
        var size = CGSize(width: 800, height: 600)
        let positionValue = AXValueCreate(.cgPoint, &point)!
        let sizeValue = AXValueCreate(.cgSize, &size)!
        precondition(AXWindowCloseBackend.windowFrame(position: positionValue, size: sizeValue) == frame)
        precondition(AXWindowCloseBackend.windowFrame(position: sizeValue, size: positionValue) == nil)
        precondition(AXWindowCloseBackend.windowFrame(position: "bad" as CFString, size: sizeValue) == nil)
        print("PASS: 严格关闭匹配、权限拒绝、歧义/标题变化/窗口消失、关闭按钮错误、AXValue 解码")
    }
}
