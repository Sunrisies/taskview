import AppKit
import ScreenCaptureKit

enum ThumbnailService {

    /// 按当前清晰度设置截取单个窗口；每次调用只截图一次，不创建常驻视频流。
    static func capture(_ window: SCWindow) async throws -> NSImage {
        let maxPixelSize = await MainActor.run { CGFloat(AppSettings.shared.preferences.thumbnailPixels) }
        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else {
            throw CocoaError(.fileNoSuchFile)
        }

        // 按最长边限制像素尺寸，避免大窗口和高分辨率屏幕占用过多缩略图内存。
        var pixelWidth = frame.width * scale
        var pixelHeight = frame.height * scale
        let longest = max(pixelWidth, pixelHeight)
        if longest > maxPixelSize {
            let factor = maxPixelSize / longest
            pixelWidth *= factor
            pixelHeight *= factor
        }
        config.width = Int(pixelWidth.rounded())
        config.height = Int(pixelHeight.rounded())
        config.showsCursor = false
        if #available(macOS 14.2, *) {
            config.includeChildWindows = false
        }

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                 configuration: config)
        return NSImage(cgImage: cgImage,
                       size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
