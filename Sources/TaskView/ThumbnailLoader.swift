import AppKit

/// 按可见卡片调度截图：同时最多四个，仅保留当前可见图片，不把浏览过的全部窗口留在内存。
@MainActor
final class ThumbnailLoader<Item> {
    private let capture: (Item) async throws -> NSImage
    private let concurrency: Int
    private var items: [Item] = []
    private var wanted: [Int] = []
    private var images: [Int: NSImage] = [:]
    private var failed: Set<Int> = []
    private var jobs: [UUID: Task<Void, Never>] = [:]
    private var active: [UUID: (session: Int, index: Int)] = [:]
    private var session = 0
    var onImageChanged: ((Int, NSImage?) -> Void)?

    init(concurrency: Int = 4, capture: @escaping (Item) async throws -> NSImage) {
        precondition(concurrency > 0)
        self.concurrency = concurrency
        self.capture = capture
    }

    func begin(items: [Item]) {
        reset()
        self.items = items
    }

    func request(indices: [Int]) {
        var seen: Set<Int> = []
        wanted = indices.filter { items.indices.contains($0) && seen.insert($0).inserted }
        let wantedSet = Set(wanted)
        for index in Array(images.keys) where !wantedSet.contains(index) {
            images.removeValue(forKey: index)
            onImageChanged?(index, nil)
        }
        // 搜索或分组重建卡片后，把仍可见的已完成图片重新交给新卡片。
        for index in wanted {
            if let image = images[index] { onImageChanged?(index, image) }
        }
        pump()
    }

    func reset() {
        session += 1
        jobs.values.forEach { $0.cancel() }
        // 系统截图未必立即响应取消，保留槽位直到真正返回，跨快速开关也不超出并发上限。
        items = []
        wanted = []
        images = [:]
        failed = []
    }

    private func pump() {
        while jobs.count < concurrency {
            let running = Set(active.values.filter { $0.session == session }.map(\.index))
            guard let index = wanted.first(where: { images[$0] == nil && !failed.contains($0) && !running.contains($0) }) else { return }
            let id = UUID()
            let requestSession = session
            let item = items[index]
            let capture = self.capture
            active[id] = (requestSession, index)
            jobs[id] = Task { @MainActor [weak self] in
                let image: NSImage?
                if Task.isCancelled { image = nil } else { image = try? await capture(item) }
                guard let self else { return }
                self.jobs.removeValue(forKey: id)
                self.active.removeValue(forKey: id)
                if !Task.isCancelled, self.session == requestSession, self.wanted.contains(index) {
                    if let image {
                        self.images[index] = image
                        self.onImageChanged?(index, image)
                    } else {
                        // 本次打开失败后不自动重试，避免错误导致无限截图循环。
                        self.failed.insert(index)
                    }
                }
                self.pump()
            }
        }
    }
}
