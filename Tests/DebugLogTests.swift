import Foundation

/// 在临时目录验证日志轮转，避免测试写入用户的正式日志。
@main
struct DebugLogTests {
    static func main() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("debug.log")
        let file = RotatingLogFile(url: url, maxBytes: 10)
        try file.append(Data("123456".utf8))
        try file.append(Data("abcdef".utf8))
        let current = try Data(contentsOf: url)
        precondition(current == Data("abcdef".utf8))
        let backup = try Data(contentsOf: url.appendingPathExtension("1"))
        precondition(backup == Data("123456".utf8))
        try file.append(Data("abcdefghijklmnop".utf8))
        let truncated = try Data(contentsOf: url)
        precondition(truncated.count == 10)
        let rotated = try Data(contentsOf: url.appendingPathExtension("1"))
        precondition(rotated == Data("abcdef".utf8))
        try Data("000000000011111111112222222222".utf8).write(to: url)
        try file.append(Data("new".utf8))
        let legacyTail = try Data(contentsOf: url.appendingPathExtension("1"))
        precondition(legacyTail == Data("2222222222".utf8), "旧版超大日志只保留有限尾部")
        var evaluated = false
        func expensiveMessage() -> String { evaluated = true; return "test" }
        DebugLog.write(expensiveMessage())
        precondition(!evaluated, "发布版关闭日志时不得计算日志内容")
        print("PASS: 日志轮转、超长写入限制、发布版关闭日志")
    }
}
