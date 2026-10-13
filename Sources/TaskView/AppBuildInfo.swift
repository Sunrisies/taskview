import Foundation

/// 启动时固定当前应用的信息；运行位置与构建渠道分别展示，不用路径猜测下载来源。
struct AppBuildInfo {
    static let current = AppBuildInfo(info: Bundle.main.infoDictionary ?? [:], path: Bundle.main.bundlePath)
    let info: [String: Any]
    let path: String

    var versionText: String {
        "\(info["CFBundleShortVersionString"] as? String ?? "未知")（构建 \(info["CFBundleVersion"] as? String ?? "未知")）"
    }

    var channelText: String {
        switch info["TaskViewBuildChannel"] as? String {
        case "local": return "本地开发构建"
        case "beta": return "Beta 发布构建"
        case "stable": return "正式发布构建"
        default: return "未知（旧版本未记录）"
        }
    }

    /// 构建记录使用 UTC 保存，界面按查看者的本机时区显示中文时间。
    static func displayDate(_ raw: String, timeZone: TimeZone = .autoupdatingCurrent) -> String? {
        let parser = ISO8601DateFormatter()
        var date = parser.date(from: raw)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = parser.date(from: raw)
        }
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy年M月d日 HH:mm:ss"
        return formatter.string(from: date)
    }

    var details: String {
        var lines = ["版本：\(versionText)", "构建渠道：\(channelText)"]
        if let date = info["TaskViewBuildDate"] as? String {
            lines.append("构建时间：\(Self.displayDate(date) ?? "未知")（本机时间）")
        }
        if let commit = info["TaskViewSourceRevision"] as? String, !commit.isEmpty {
            let dirty = info["TaskViewSourceDirty"] as? Bool == true ? "（含未提交修改）" : ""
            lines.append("源码提交：\(commit)\(dirty)")
        }
        lines.append("运行位置：\(path)")
        return lines.joined(separator: "\n")
    }
}
