import Foundation

/// 辅助功能接口没有公开的窗口 ID 查询；综合标题和几何信息匹配，拒绝并列候选。
enum WindowMatcher {
    struct Candidate {
        let title: String?
        let frame: CGRect
    }

    static func closeIndex(candidates: [Candidate], title: String?, frame: CGRect) -> Int? {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scores = candidates.map { candidate -> Int in
            let other = candidate.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard frame.width > 0, frame.height > 0, candidate.frame.width > 0, candidate.frame.height > 0,
                  abs(candidate.frame.minX - frame.minX) < 4,
                  abs(candidate.frame.minY - frame.minY) < 4,
                  abs(candidate.frame.width - frame.width) < 8,
                  abs(candidate.frame.height - frame.height) < 8,
                  title.isEmpty || other.isEmpty || title == other else { return 0 }
            return !title.isEmpty && title == other ? 2 : 1
        }
        guard let best = scores.max(), best > 0 else { return nil }
        let matches = scores.indices.filter { scores[$0] == best }
        return matches.count == 1 ? matches[0] : nil
    }

    static func bestIndex(candidates: [Candidate], title: String?, frame: CGRect) -> Int? {
        let target = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scores = candidates.map { candidate -> Int in
            guard candidate.frame.width > 0, candidate.frame.height > 0 else { return 0 }
            let candidateTitle = candidate.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let exact = !target.isEmpty && target == candidateTitle
            let partial = !target.isEmpty && !candidateTitle.isEmpty
                && (target.hasPrefix(candidateTitle) || candidateTitle.hasPrefix(target))
            let geometry = abs(candidate.frame.minX - frame.minX) < 4
                && abs(candidate.frame.minY - frame.minY) < 4
                && abs(candidate.frame.width - frame.width) < 8
                && abs(candidate.frame.height - frame.height) < 8
            if geometry { return exact ? 5 : (partial ? 4 : 3) }
            return exact ? 2 : 0
        }
        guard let best = scores.max(), best >= 2 else { return nil }
        let matches = scores.indices.filter { scores[$0] == best }
        return matches.count == 1 ? matches[0] : nil
    }
}
