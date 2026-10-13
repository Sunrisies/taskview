import Foundation
import CoreGraphics

/// 真实坐标转换和查询逻辑使用测试元信息，不依赖屏幕录制权限。
private struct Metadata: WindowMetadata {
    let pid: pid_t
    let title: String
    let appName: String
    let frame: CGRect
}

@main
struct WindowQueryTests {
    static func main() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let left = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        let items = [Metadata(pid: 1, title: "项目报告", appName: "Mail", frame: CGRect(x: 0, y: 0, width: 600, height: 400)),
                     Metadata(pid: 2, title: "Café / README", appName: "Browser", frame: CGRect(x: -600, y: 100, width: 500, height: 400)),
                     Metadata(pid: 1, title: "Draft", appName: "Mail", frame: CGRect(x: 100, y: 100, width: 500, height: 400))]
        precondition(WindowQuery.groups(items: items, search: "项目 MAIL", screen: nil, grouped: false).flatMap(\.indices) == [0])
        precondition(WindowQuery.groups(items: items, search: "CAFE readme", screen: nil, grouped: false).flatMap(\.indices) == [1])
        precondition(WindowQuery.groups(items: items, search: "   ", screen: main, grouped: false).flatMap(\.indices) == [0, 2])
        precondition(WindowQuery.groups(items: items, search: "", screen: left, grouped: false).flatMap(\.indices) == [1])
        precondition(WindowQuery.groups(items: items, search: "不存在", screen: nil, grouped: true).isEmpty)
        let groups = WindowQuery.groups(items: items, search: "", screen: nil, grouped: true)
        precondition(groups.map(\.indices) == [[0, 2], [1]] && groups.map(\.name) == ["Mail", "Browser"])
        precondition(WindowQuery.screenRect(appKitFrame: main, primaryScreenTop: 900) == main)
        let above = CGRect(x: 0, y: 900, width: 1280, height: 800)
        precondition(WindowQuery.screenRect(appKitFrame: above, primaryScreenTop: 900).minY == -800)
        let below = CGRect(x: -1280, y: -800, width: 1280, height: 800)
        let converted = WindowQuery.screenRect(appKitFrame: below, primaryScreenTop: 900)
        precondition(converted.minX == -1280 && converted.minY == 900)
        print("PASS: 中文/多词/大小写搜索、稳定分组、显示器筛选与上下左右副屏坐标")
    }
}
