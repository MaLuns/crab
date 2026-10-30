import AppKit

final class FilenameRepairWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private struct Row {
        let source: URL
        let candidates: [FilenameRepairCandidate]
        var selectedIndex = 0
        var appliedName: String?
        var proposed: FilenameRepairCandidate? {
            candidates.indices.contains(selectedIndex - 1) ? candidates[selectedIndex - 1] : nil
        }
    }
    private var rows: [Row]
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let apply = NSButton(title: L("确认改名…"), target: nil, action: nil)
    private let reveal = NSButton(title: L("在访达中显示"), target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private var busy = false
    private let store: ConfigurationStore

    init(urls: [URL], store: ConfigurationStore = .shared) {
        self.store = store
        let repair = FilenameRepair()
        var seen = Set<URL>()
        rows = urls.filter { seen.insert($0.standardizedFileURL).inserted }.map {
            Row(source: $0.standardizedFileURL, candidates: repair.candidates(for: $0.lastPathComponent))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = L("修复乱码文件名")
        window.titlebarAppearsTransparent = true
        window.isOpaque = false; window.backgroundColor = .clear
        window.minSize = NSSize(width: 760, height: 350)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        WindowAppearance.bind(window, to: store)
        build(window)
        updateStatus()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(_ window: NSWindow) {
        let background = NSVisualEffectView()
        background.material = .underWindowBackground; background.blendingMode = .behindWindow
        background.state = .followsWindowActiveState
        window.contentView = background
        let explanation = NSTextField(wrappingLabelWithString: L("候选仅表示编码转换可逆，无法据此确定原本名称。请逐项选择并核对；保持原名的项目不会修改。含“�”的名称通常已丢失原字节，无法可靠还原。"))
        explanation.font = .systemFont(ofSize: 13)
        explanation.textColor = .secondaryLabelColor
        table.delegate = self; table.dataSource = self
        table.backgroundColor = .clear; table.rowHeight = 32; table.style = .fullWidth
        for (id, title, width) in [("original", "原名", 230.0), ("candidate", "预览 / 选择候选", 300.0), ("encoding", "转换依据", 290.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = L(title); column.width = width; column.minWidth = 120
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.documentView = table
        apply.target = self; apply.action = #selector(confirmApply); apply.bezelStyle = .rounded
        apply.image = CrabSymbol.image(named: "check", size: 15); apply.imagePosition = .imageLeading
        reveal.target = self; reveal.action = #selector(revealSelection); reveal.bezelStyle = .rounded
        reveal.image = CrabSymbol.image(named: "folder", size: 15); reveal.imagePosition = .imageLeading
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        spinner.widthAnchor.constraint(equalToConstant: 16).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 16).isActive = true
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        [apply, reveal, spinner].forEach { $0.setContentHuggingPriority(.required, for: .horizontal) }
        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: 1).isActive = true
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        let actions = NSStackView(views: [apply, reveal, spinner, spacer])
        actions.orientation = .horizontal; actions.alignment = .centerY; actions.distribution = .fill; actions.spacing = 12
        let column = NSStackView(views: [explanation, scroll, status, actions])
        column.orientation = .vertical; column.alignment = .leading; column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
            column.topAnchor.constraint(equalTo: background.topAnchor, constant: 42),
            column.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -20),
            explanation.widthAnchor.constraint(equalTo: column.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: column.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            status.widthAnchor.constraint(equalTo: column.widthAnchor)
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let item = rows[row]
        if tableColumn?.identifier.rawValue == "candidate", item.appliedName == nil, !item.candidates.isEmpty {
            let popup = FilenameRepairChoice(frame: .zero, pullsDown: false)
            popup.addItem(withTitle: L("保持原名"))
            for candidate in item.candidates { popup.addItem(withTitle: candidate.name) }
            popup.selectItem(at: item.selectedIndex)
            popup.font = .systemFont(ofSize: 13)
            popup.isEnabled = !busy
            popup.changed = { [weak self] index in
                guard let self, let indexInRows = self.rows.firstIndex(where: { $0.source == item.source }) else { return }
                self.rows[indexInRows].selectedIndex = index
                self.table.reloadData(forRowIndexes: IndexSet(integer: indexInRows), columnIndexes: IndexSet(integer: 2))
                self.updateStatus()
            }
            return popup
        }
        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: 13); field.lineBreakMode = .byTruncatingMiddle
        field.toolTip = item.source.path
        switch tableColumn?.identifier.rawValue {
        case "candidate": field.stringValue = item.appliedName ?? L("没有可逆转换候选")
        case "encoding":
            field.stringValue = item.appliedName == nil ? (item.proposed?.explanation ?? L("保持原名")) : L("已完成")
            field.textColor = .secondaryLabelColor
        default: field.stringValue = item.source.lastPathComponent
        }
        return field
    }

    private var mapping: [URL: String] {
        Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            guard row.appliedName == nil, let candidate = row.proposed else { return nil }
            return (row.source, candidate.name)
        })
    }
    private func updateStatus() {
        let count = mapping.count
        apply.isEnabled = !busy && count > 0
        if !busy { status.stringValue = LF("共 %d 项，已选择 %d 项改名。", rows.count, count) }
    }

    @objc private func confirmApply() {
        guard let window, !busy else { return }
        let changes = mapping
        guard !changes.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = LF("将 %d 个项目改为以下名称？", changes.count)
        let preview = changes.sorted { $0.key.path < $1.key.path }.prefix(12).map { "\($0.key.lastPathComponent) → \($0.value)" }.joined(separator: "\n")
        alert.informativeText = preview + (changes.count > 12 ? LF("\n……其余 %d 项见预览表。", changes.count - 12) : "")
        alert.addButton(withTitle: L("应用改名")); alert.addButton(withTitle: L("取消"))
        WindowAppearance.bind(alert.window, to: store)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.perform(changes)
        }
    }

    private func perform(_ changes: [URL: String]) {
        busy = true; apply.isEnabled = false; reveal.isEnabled = false
        window?.standardWindowButton(.closeButton)?.isEnabled = false
        status.stringValue = L("正在改名；发生失败时将恢复原名…")
        spinner.startAnimation(nil); table.reloadData()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                _ = try FilenameRepair().apply(mapping: changes)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    for index in self.rows.indices {
                        if let name = changes[self.rows[index].source] { self.rows[index].appliedName = name }
                    }
                    self.finish()
                    self.status.stringValue = LF("已完成 %d 项改名。", changes.count)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let window = self.window else { return }
                    self.finish(); self.status.stringValue = error.localizedDescription
                    WindowDialogs.present(WindowAppearance.errorAlert(error, store: self.store), for: window, store: self.store)
                }
            }
        }
    }

    private func finish() {
        busy = false; reveal.isEnabled = true
        window?.standardWindowButton(.closeButton)?.isEnabled = true
        spinner.stopAnimation(nil); table.reloadData(); updateStatus()
    }

    @objc private func revealSelection() {
        guard rows.indices.contains(table.selectedRow) else { return }
        let row = rows[table.selectedRow]
        let url = row.appliedName.map { row.source.deletingLastPathComponent().appendingPathComponent($0) } ?? row.source
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private final class FilenameRepairChoice: NSPopUpButton {
    var changed: ((Int) -> Void)?
    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: flag)
        target = self; action = #selector(selectCandidate)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func selectCandidate() { changed?(indexOfSelectedItem) }
}
