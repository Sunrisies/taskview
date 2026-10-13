import AppKit

/// 用受控异步截图模拟无法立即取消的系统任务，验证并发上限和视口淘汰。
@MainActor
private final class CaptureProbe {
    var started: [Int] = []
    var pending: [Int: CheckedContinuation<NSImage, Error>] = [:]
    var active = 0
    var peak = 0
    func capture(_ item: Int) async throws -> NSImage {
        active += 1
        peak = max(peak, active)
        started.append(item)
        defer { active -= 1 }
        return try await withCheckedThrowingContinuation { pending[item] = $0 }
    }
    func finish(_ item: Int, success: Bool = true) {
        guard let continuation = pending.removeValue(forKey: item) else { fatalError("截图尚未开始：\(item)") }
        if success { continuation.resume(returning: NSImage(size: NSSize(width: 8, height: 8))) }
        else { continuation.resume(throwing: CocoaError(.fileNoSuchFile)) }
    }
}

@main
struct ThumbnailLoaderTests {
    @MainActor
    static func settle() async { try? await Task.sleep(nanoseconds: 20_000_000) }
    @MainActor
    static func main() async {
        let probe = CaptureProbe()
        let loader = ThumbnailLoader<Int> { try await probe.capture($0) }
        var ready: [Int] = []
        var evicted: [Int] = []
        loader.onImageChanged = { index, image in
            if image != nil { ready.append(index) } else { evicted.append(index) }
        }
        loader.begin(items: Array(0..<100))
        loader.request(indices: [0, 1, 2, 3, 4, 5])
        await settle()
        precondition(Set(probe.started) == [0, 1, 2, 3] && probe.peak == 4)
        loader.request(indices: [50, 51])
        precondition(probe.started.count == 4, "滚动不能越过仍在执行的截图槽位")
        probe.finish(0); probe.finish(1)
        await settle()
        precondition(Set(probe.started.suffix(2)) == [50, 51])
        probe.finish(2); probe.finish(3); probe.finish(50); probe.finish(51)
        await settle()
        precondition(Set(ready) == [50, 51], "已经离开视口的旧截图不能回填")
        precondition(!probe.started.contains(4) && !probe.started.contains(5), "不应截图旧视口排队项")
        loader.request(indices: [70])
        await settle()
        precondition(Set(evicted) == [50, 51], "离开视口必须清除卡片的图片引用")
        probe.finish(70, success: false)
        await settle()
        let count = probe.started.count
        loader.request(indices: [70])
        await settle()
        precondition(probe.started.count == count, "失败不能产生无限重试")
        loader.begin(items: Array(1000..<1010))
        loader.request(indices: [0, 1, 2, 3])
        await settle()
        precondition(Set(probe.pending.keys) == [1000, 1001, 1002, 1003])
        loader.begin(items: Array(2000..<2010))
        loader.request(indices: [0, 1, 2, 3])
        await settle()
        precondition(!probe.started.contains(2000), "新打开要等待不能立即取消的旧系统截图结束")
        for item in 1000...1003 { probe.finish(item) }
        await settle()
        precondition(Set(probe.pending.keys) == [2000, 2001, 2002, 2003] && probe.peak <= 4)
        loader.reset()
        for item in 2000...2003 { probe.finish(item) }
        await settle()
        precondition(probe.active == 0 && probe.pending.isEmpty)
        print("PASS: 可见卡片优先、滚动淘汰、迟到结果丢弃、失败不循环、跨快速开关最多四路截图")
    }
}
