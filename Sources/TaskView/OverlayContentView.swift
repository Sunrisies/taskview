import AppKit

/// 覆盖层内容：搜索、显示器筛选、应用分组、可滚动网格和键盘导航。
final class OverlayContentView: NSView, NSSearchFieldDelegate {
    var onFocusSelected: ((Int) -> Void)?
    var onCloseRequested: (() -> Void)?
    var onCloseWindow: ((Int) -> Void)?
    var onVisibleIndicesChanged: (([Int]) -> Void)?
    var onScopeChanged: ((WindowScope) -> Void)?
    var onGroupingChanged: ((Bool) -> Void)?
    private(set) var items: [WindowItem] = []
    private(set) var displayedIndices: [Int] = []
    private(set) var selectedIndex = 0
    var hoverSelection = true

    private var scope: WindowScope = .allDisplays
    private var grouping = false
    private var targetScreenRect: CGRect?
    private var groups: [WindowQuery.Group] = []
    private var cells: [WindowCellView] = []
    private var groupLabels: [NSTextField] = []
    private var navigationRows: [[Int]] = []
    private var lastVisible: [Int] = []
    private var isUpdatingLayout = false
    private var appliedSearch = ""
    private var boundsObserver: NSObjectProtocol?
    private let gridScroll = NSScrollView()
    private let gridContainer = WindowGridView()
    private let searchField = NSSearchField()
    private let scopePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let groupToggle = NSButton(checkboxWithTitle: "按应用分组", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "任务视图")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let footerLabel = NSTextField(labelWithString: "输入文字搜索    ↑ ↓ 选择    ↩ 打开    ⌘⌫ 关闭窗口    Esc 清空搜索 / 退出")
    private let emptyLabel = NSTextField(labelWithString: "当前空间没有其他窗口")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        gridScroll.hasVerticalScroller = true
        gridScroll.autohidesScrollers = true
        gridScroll.drawsBackground = false
        gridScroll.documentView = gridContainer
        gridScroll.contentView.postsBoundsChangedNotifications = true
        addSubview(gridScroll)
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: gridScroll.contentView, queue: .main) { [weak self] _ in self?.notifyVisibleIndices() }

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        addSubview(titleLabel)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        subtitleLabel.alignment = .center
        addSubview(subtitleLabel)
        searchField.placeholderString = "搜索窗口标题或应用名…"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        addSubview(searchField)
        scopePicker.addItems(withTitles: ["所有显示器", "当前显示器"])
        scopePicker.target = self
        scopePicker.action = #selector(scopeChanged)
        addSubview(scopePicker)
        groupToggle.target = self
        groupToggle.action = #selector(groupingChanged)
        addSubview(groupToggle)
        footerLabel.font = .systemFont(ofSize: 12)
        footerLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        footerLabel.alignment = .center
        addSubview(footerLabel)
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        emptyLabel.alignment = .center
        addSubview(emptyLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) } }

    /// 打开时以鼠标所在显示器为筛选目标；偏好由协调器传入，视图不写用户设置。
    func configure(scope: WindowScope, grouped: Bool, screenRect: CGRect?) {
        self.scope = scope
        grouping = grouped
        targetScreenRect = screenRect
        scopePicker.selectItem(at: scope == .allDisplays ? 0 : 1)
        groupToggle.state = grouped ? .on : .off
        rebuild()
    }

    func setItems(_ newItems: [WindowItem]) {
        items = newItems
        searchField.stringValue = ""
        selectedIndex = 0
        displayedIndices = []
        rebuild()
    }

    /// 搜索只过滤已有元信息，不重新读系统窗口，也不主动截取所有匹配项。
    func setSearch(_ text: String) {
        searchField.stringValue = text
        rebuild()
    }

    private func rebuild() {
        isUpdatingLayout = true
        appliedSearch = searchField.stringValue
        let previousSource = displayedIndices.indices.contains(selectedIndex) ? displayedIndices[selectedIndex] : nil
        cells.forEach { $0.removeFromSuperview() }
        groupLabels.forEach { $0.removeFromSuperview() }
        cells = []
        groupLabels = []
        navigationRows = []
        groups = WindowQuery.groups(items: items, search: searchField.stringValue,
            screen: scope == .currentDisplay ? targetScreenRect : nil, grouped: grouping)
        displayedIndices = groups.flatMap(\.indices)
        selectedIndex = previousSource.flatMap { displayedIndices.firstIndex(of: $0) } ?? 0
        cells = displayedIndices.enumerated().map { displayIndex, sourceIndex in
            let cell = WindowCellView(itemIndex: sourceIndex)
            cell.configure(with: items[sourceIndex])
            cell.onHover = { [weak self] _ in
                if self?.hoverSelection == true { self?.select(displayIndex, scroll: false) }
            }
            cell.onSelect = { [weak self] source in self?.onFocusSelected?(source) }
            cell.onClose = { [weak self] source in self?.onCloseWindow?(source) }
            gridContainer.addSubview(cell)
            return cell
        }
        for group in groups where group.name != nil {
            let label = NSTextField(labelWithString: "\(group.name!) · \(group.indices.count) 个窗口")
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .white
            gridContainer.addSubview(label)
            groupLabels.append(label)
        }
        gridScroll.isHidden = displayedIndices.isEmpty
        emptyLabel.isHidden = !displayedIndices.isEmpty
        emptyLabel.stringValue = !searchField.stringValue.isEmpty ? "没有匹配的窗口，试试其他标题或应用名"
            : (scope == .currentDisplay ? "当前显示器没有其他窗口" : "当前空间没有其他窗口")
        subtitleLabel.stringValue = "\(displayedIndices.count) / \(items.count) 个窗口"
        if !cells.isEmpty { cells[selectedIndex].isSelected = true }
        // 新卡片需要重放已经完成的可见图片；即使原始索引相同，也重新通知一次。
        lastVisible = []
        needsLayout = true
        isUpdatingLayout = false
        layoutSubtreeIfNeeded()
        notifyVisibleIndices(force: true)
    }

    /// 图片回调使用原始索引，不能把异步返回的图片交给搜索后同位置的另一张卡片。
    func setThumbnail(_ image: NSImage?, at sourceIndex: Int) {
        guard let displayIndex = displayedIndices.firstIndex(of: sourceIndex) else { return }
        cells[displayIndex].setThumbnail(image)
    }

    var visibleSourceIndices: [Int] {
        let visible = gridScroll.documentVisibleRect
        return cells.filter { $0.frame.width > 0 && $0.frame.intersects(visible) }.map(\.itemIndex)
    }

    private func notifyVisibleIndices(force: Bool = false) {
        guard !isUpdatingLayout else { return }
        let indices = gridScroll.isHidden ? [] : visibleSourceIndices
        guard force || indices != lastVisible else { return }
        lastVisible = indices
        onVisibleIndicesChanged?(indices)
    }

    // MARK: - 选择和搜索

    func select(_ index: Int, scroll: Bool = true) {
        guard !cells.isEmpty else { return }
        let clamped = max(0, min(index, cells.count - 1))
        let previous = selectedIndex
        selectedIndex = clamped
        if previous != clamped { cells[previous].isSelected = false }
        if !cells[clamped].isSelected { cells[clamped].isSelected = true }
        if scroll { gridContainer.scrollToVisible(cells[clamped].frame) }
        notifyVisibleIndices()
    }

    private func moveVertically(_ delta: Int) {
        guard let row = navigationRows.firstIndex(where: { $0.contains(selectedIndex) }),
              let column = navigationRows[row].firstIndex(of: selectedIndex) else { return }
        let next = max(0, min(row + delta, navigationRows.count - 1))
        select(navigationRows[next][min(column, navigationRows[next].count - 1)])
    }

    private func confirmSelection() {
        guard displayedIndices.indices.contains(selectedIndex) else { return }
        onFocusSelected?(displayedIndices[selectedIndex])
    }

    private func escape() {
        if !searchField.stringValue.isEmpty {
            setSearch("")
            window?.makeFirstResponder(self)
        } else { onCloseRequested?() }
    }

    @objc private func searchChanged() {
        if appliedSearch != searchField.stringValue { rebuild() }
    }
    func controlTextDidChange(_ notification: Notification) { searchChanged() }
    @objc private func scopeChanged() {
        scope = scopePicker.indexOfSelectedItem == 0 ? .allDisplays : .currentDisplay
        onScopeChanged?(scope)
        rebuild()
    }
    @objc private func groupingChanged() {
        grouping = groupToggle.state == .on
        onGroupingChanged?(grouping)
        rebuild()
    }

    /// 搜索输入保留原生输入法与左右移动光标；上下箭头、回车和 Esc 操作结果网格。
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)): moveVertically(-1)
        case #selector(NSResponder.moveDown(_:)): moveVertically(1)
        case #selector(NSResponder.insertNewline(_:)): confirmSelection()
        case #selector(NSResponder.cancelOperation(_:)): escape()
        default: return false
        }
        return true
    }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51, event.modifierFlags.contains(.command) {
            if displayedIndices.indices.contains(selectedIndex) { onCloseWindow?(displayedIndices[selectedIndex]) }
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
            window?.makeFirstResponder(searchField)
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCloseRequested?()
            return
        }
        switch event.keyCode {
        case 53: escape()
        case 123: if !cells.isEmpty { select((selectedIndex - 1 + cells.count) % cells.count) }
        case 124: if !cells.isEmpty { select((selectedIndex + 1) % cells.count) }
        case 126: moveVertically(-1)
        case 125: moveVertically(1)
        case 36, 76, 49: confirmSelection()
        default:
            if !event.modifierFlags.intersection([.command, .control]).isEmpty {
                // 网格没有其他编辑操作；交回响应链会被覆盖窗口再次转发，形成递归。
                return
            } else if let characters = event.characters, !characters.isEmpty,
                      !characters.unicodeScalars.contains(where: {
                          CharacterSet.controlCharacters.contains($0) || (0xF700...0xF8FF).contains($0.value)
                      }),
                      event.keyCode < 123 {
                // 交给系统文本编辑器处理输入，支持中文组合输入，避免手工拼接键盘字符。
                window?.makeFirstResponder(searchField)
                searchField.currentEditor()?.keyDown(with: event)
            } else {
                // 退格、Delete、功能键等在网格中不执行操作；搜索编辑由原生文本视图处理。
                return
            }
        }
    }
    override func cancelOperation(_ sender: Any?) { escape() }
    override func mouseDown(with event: NSEvent) { onCloseRequested?() }

    // MARK: - 分组网格布局

    override func layout() {
        super.layout()
        isUpdatingLayout = true
        defer { isUpdatingLayout = false; notifyVisibleIndices() }
        let width = bounds.width
        let height = bounds.height
        titleLabel.frame = CGRect(x: 0, y: height - 70, width: width, height: 28)
        subtitleLabel.frame = CGRect(x: 0, y: height - 90, width: width, height: 16)
        let toolbarWidth = min(780, max(260, width - 96))
        let toolbarX = (width - toolbarWidth) / 2
        searchField.frame = CGRect(x: toolbarX, y: height - 130, width: max(100, toolbarWidth - 280), height: 28)
        scopePicker.frame = CGRect(x: toolbarX + toolbarWidth - 264, y: height - 130, width: 136, height: 28)
        groupToggle.frame = CGRect(x: toolbarX + toolbarWidth - 116, y: height - 129, width: 116, height: 24)
        footerLabel.frame = CGRect(x: 0, y: 30, width: width, height: 16)
        emptyLabel.frame = CGRect(x: 0, y: height / 2 - 10, width: width, height: 20)
        guard !cells.isEmpty else { navigationRows = []; notifyVisibleIndices(); return }
        let rect = CGRect(x: 64, y: 70, width: max(width - 128, 100), height: max(height - 230, 100))
        gridScroll.frame = rect
        let gridWidth = gridScroll.contentSize.width
        let gap: CGFloat = 18
        let fitting = max(1, Int((gridWidth + gap) / (180 + gap)))
        let estimated = Int((Double(gridWidth) * Double(cells.count) / (Double(rect.height) * 1.55)).squareRoot().rounded())
        let columns = max(1, min(estimated, min(cells.count, fitting)))
        let cellWidth = min(480, max(1, (gridWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)))
        let rowCount = groups.reduce(0) { $0 + Int(ceil(Double($1.indices.count) / Double(columns))) }
        let headingSpace: CGFloat = grouping ? CGFloat(groups.count) * 38 : 0
        let cellHeight = max(130, min(cellWidth / 1.55, (rect.height - headingSpace - gap * CGFloat(max(0, rowCount - 1))) / CGFloat(max(1, rowCount))))
        let totalHeight = CGFloat(rowCount) * (cellHeight + gap) - gap + headingSpace
        let contentHeight = max(rect.height, totalHeight)
        gridContainer.frame = CGRect(x: 0, y: 0, width: gridWidth, height: contentHeight)
        var y = (contentHeight - totalHeight) / 2
        var displayOffset = 0
        var labelIndex = 0
        navigationRows = []
        for group in groups {
            if group.name != nil {
                groupLabels[labelIndex].frame = CGRect(x: 4, y: y, width: gridWidth - 8, height: 24)
                labelIndex += 1
                y += 38
            }
            for start in stride(from: 0, to: group.indices.count, by: columns) {
                let count = min(columns, group.indices.count - start)
                let rowWidth = CGFloat(count) * cellWidth + CGFloat(count - 1) * gap
                var row: [Int] = []
                for column in 0..<count {
                    let index = displayOffset + start + column
                    cells[index].frame = CGRect(x: (gridWidth - rowWidth) / 2 + CGFloat(column) * (cellWidth + gap),
                                                y: y, width: cellWidth, height: cellHeight)
                    row.append(index)
                }
                navigationRows.append(row)
                y += cellHeight + gap
            }
            displayOffset += group.indices.count
        }
        gridContainer.scrollToVisible(cells[selectedIndex].frame)
        notifyVisibleIndices()
    }
}

private final class WindowGridView: NSView {
    override var isFlipped: Bool { true }
}
