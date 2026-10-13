import Foundation

/// 事件诊断日志：发布版默认关闭，用 --debug-log 开启；调试版默认开启。
/// 写入放到串行后台队列，最多保留当前日志和一个历史文件，避免长期驻留时无限增长。
enum DebugLog {
    private static let queue = DispatchQueue(label: "com.zhuzhongqian.taskview.logging", qos: .utility)
    private static let formatter = ISO8601DateFormatter()
    private static let file = RotatingLogFile(url: URL(fileURLWithPath:
        NSHomeDirectory() + "/Library/Application Support/TaskView/debug.log"))
    private static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return CommandLine.arguments.contains("--debug-log")
        #endif
    }

    /// 关闭日志时不计算插值内容，也不创建目录或执行磁盘写入。
    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let message = String(message().prefix(2048))
        queue.async {
            let line = "[\(formatter.string(from: Date()))] \(message)\n"
            if let data = line.data(using: .utf8) { try? file.append(data) }
        }
    }
}

/// 同步文件写入器，由上面的串行队列调用；可用临时目录单独验证轮转行为。
final class RotatingLogFile {
    private let url: URL
    private let maxBytes: Int
    init(url: URL, maxBytes: Int = 1_048_576) {
        precondition(maxBytes > 0)
        self.url = url
        self.maxBytes = maxBytes
    }

    func append(_ data: Data) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let chunk = Data(data.prefix(maxBytes))
        let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if size + chunk.count > maxBytes {
            let backup = url.appendingPathExtension("1")
            if manager.fileExists(atPath: backup.path) { try manager.removeItem(at: backup) }
            if size > maxBytes {
                // 兼容旧版不限大小的日志，只保留尾部，首次升级也不留下巨型备份。
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(size - maxBytes))
                let tail = try handle.read(upToCount: maxBytes) ?? Data()
                try tail.write(to: backup)
                try manager.removeItem(at: url)
            } else if manager.fileExists(atPath: url.path) {
                try manager.moveItem(at: url, to: backup)
            }
        }
        if manager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: chunk)
        } else {
            try chunk.write(to: url)
        }
    }
}
