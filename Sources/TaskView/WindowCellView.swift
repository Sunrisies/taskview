import AppKit

/// 单张窗口卡片，负责缩略图、标题、选中样式和鼠标事件。
final class WindowCellView: NSView {
    let itemIndex: Int
    private let iconView = NSImageView()
    private var appIcon: NSImage?
    private let titleLabel = NSTextField(labelWithString: "")
    private let appLabel = NSTextField(labelWithString: "")
    private let placeholderLayer = CALayer()
    private let closeButton = NSButton()

    var onHover: ((Int) -> Void)?
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?

    var isSelected = false {
        didSet { updateSelectionStyle() }
    }

    init(itemIndex: Int) {
        self.itemIndex = itemIndex
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor

        placeholderLayer.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        placeholderLayer.cornerRadius = 10
        layer?.addSublayer(placeholderLayer)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.alignment = .center
        addSubview(titleLabel)

        appLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        appLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.alignment = .center
        addSubview(appLabel)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭窗口")
        closeButton.isBordered = false
        closeButton.contentTintColor = .white
        closeButton.refusesFirstResponder = true
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        closeButton.layer?.cornerRadius = 12
        closeButton.toolTip = "关闭此窗口（⌘⌫）"
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with item: WindowItem) {
        toolTip = item.title
        closeButton.setAccessibilityLabel("关闭 \(item.appName) 的窗口：\(item.title)")
        titleLabel.stringValue = item.title
        appLabel.stringValue = item.appName
        iconView.image = item.icon
        appIcon = item.icon
        iconView.isHidden = false
    }

    func setThumbnail(_ image: NSImage?) {
        iconView.image = image ?? appIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.isHidden = false
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds.insetBy(dx: 6, dy: 6)
        placeholderLayer.frame = bounds

        let labelArea: CGFloat = 34
        let thumbHeight = max(bounds.height - labelArea, 0)
        let thumbFrame = CGRect(x: bounds.minX, y: bounds.minY + labelArea,
                                width: bounds.width, height: thumbHeight)
        iconView.frame = thumbFrame.insetBy(dx: 4, dy: 4)
        appLabel.frame = CGRect(x: bounds.minX + 4, y: bounds.minY + 18,
                               width: max(bounds.width - 8, 0), height: 14)
        titleLabel.frame = CGRect(x: bounds.minX + 4, y: bounds.minY + 3,
                                 width: max(bounds.width - 8, 0), height: 16)
        closeButton.frame = CGRect(x: bounds.maxX - 30, y: bounds.maxY - 30, width: 24, height: 24)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(itemIndex)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(itemIndex)
    }

    @objc private func closeWindow() { onClose?(itemIndex) }

    private func updateSelectionStyle() {
        if isSelected {
            layer?.borderColor = NSColor.systemBlue.cgColor
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.18).cgColor
            iconView.alphaValue = 1
        } else {
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            iconView.alphaValue = 0.95
        }
    }
}
