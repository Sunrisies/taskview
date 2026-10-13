import Foundation
import CoreGraphics

/// 查询只依赖元信息，测试无需真实系统窗口；返回原始索引，避免过滤后聚焦错位。
protocol WindowMetadata {
    var pid: pid_t { get }
    var title: String { get }
    var appName: String { get }
    var frame: CGRect { get }
}

enum WindowQuery {
    struct Group {
        let name: String?
        let indices: [Int]
    }

    static func groups<T: WindowMetadata>(items: [T], search: String,
                                          screen: CGRect?, grouped: Bool) -> [Group] {
        let terms = search.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let indices = items.indices.filter { index in
            let item = items[index]
            if let screen, !item.frame.intersects(screen) { return false }
            let text = item.title + " " + item.appName
            return terms.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil }
        }
        guard grouped else { return indices.isEmpty ? [] : [Group(name: nil, indices: indices)] }
        var order: [pid_t] = []
        var groupedIndices: [pid_t: [Int]] = [:]
        for index in indices {
            let pid = items[index].pid
            if groupedIndices[pid] == nil { order.append(pid) }
            groupedIndices[pid, default: []].append(index)
        }
        // 应用组按首次出现排序，组内保持原窗口前后顺序。
        return order.map { pid in
            let indices = groupedIndices[pid]!
            return Group(name: items[indices[0]].appName, indices: indices)
        }
    }

    /// NSScreen 使用左下角原点，窗口元信息使用主屏左上角原点；支持负坐标副屏。
    static func screenRect(appKitFrame: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: appKitFrame.minX, y: primaryScreenTop - appKitFrame.maxY,
               width: appKitFrame.width, height: appKitFrame.height)
    }
}
