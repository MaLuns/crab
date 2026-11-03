import AppKit

/// Previews one source at a time. The only write is the single batch submitted on the last page.
final class IconCropWindowController: NSWindowController, NSWindowDelegate {
    private struct Selection {
        var crop = IconCrop.centered
        var keepsWholeImage = false
        var color: NSColor
        var isTransparent: Bool

        init(format: ToolAction) {
            let background = IconExportOptions.defaultBackground(for: format)
            color = background.flatMap(NSColor.init(cgColor:)) ?? .white
            isTransparent = background == nil
        }

        var output: IconExportOptions {
            IconExportOptions(crop: keepsWholeImage ? nil : crop, backgroundColor: isTransparent ? nil : color.cgColor)
        }
    }

    private let urls: [URL]
    private let format: ToolAction
    private let export: ([URL: IconExportOptions]) -> Void
    var onClose: (() -> Void)?

    private var index = 0
    private var selections: [Selection]
    private var image: CGImage?
    private var loadID = UUID()

    private let canvas = IconCropCanvas()
    private let preview = IconResultPreview()
    private let filename = NSTextField(labelWithString: "")
    private let position = NSTextField(labelWithString: "")
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let cropButton = NSButton(radioButtonWithTitle: L("方形裁剪"), target: nil, action: nil)
    private let fitButton = NSButton(radioButtonWithTitle: L("保留整图"), target: nil, action: nil)
    private let colorWell = NSColorWell()
    private let transparentButton = NSButton(checkboxWithTitle: L("透明背景"), target: nil, action: nil)
    private let previous = NSButton(title: L("上一张"), target: nil, action: nil)
    private let advance = NSButton(title: "", target: nil, action: nil)

    init(urls: [URL], format: ToolAction, store: ConfigurationStore, export: @escaping ([URL: IconExportOptions]) -> Void) {
        precondition(!urls.isEmpty)
        self.urls = urls
        self.format = format
        self.export = export
        selections = Array(repeating: Selection(format: format), count: urls.count)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 490),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = L(format.title)
        window.contentMinSize = NSSize(width: 600, height: 465)
        window.isReleasedWhenClosed = false
        window.delegate = self
        WindowAppearance.bind(window, to: store)
        build()
        window.center()
        loadCurrent()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        guard let root = window?.contentView else { return }
        filename.font = .systemFont(ofSize: 15, weight: .semibold)
        filename.lineBreakMode = .byTruncatingMiddle
        filename.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        position.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        position.textColor = .secondaryLabelColor
        position.setContentCompressionResistancePriority(.required, for: .horizontal)

        let heading = label("图标预览", size: 13, weight: .semibold)
        preview.setAccessibilityLabel(L("图标预览"))
        canvas.setAccessibilityLabel(L("方形裁剪"))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        for button in [cropButton, fitButton] {
            button.target = self
            button.action = #selector(changeMode(_:))
        }
        colorWell.colorWellStyle = .expanded
        colorWell.setAccessibilityLabel(L("背景色"))
        colorWell.target = self
        colorWell.action = #selector(changeColor)
        colorWell.isContinuous = true
        if #available(macOS 14, *) { colorWell.supportsAlpha = false }
        transparentButton.target = self
        transparentButton.action = #selector(changeTransparency)
        transparentButton.isHidden = format == .iosIconset
        let colorRow = stack([label("背景色"), colorWell], vertical: false, spacing: 8)
        let sidebar = stack([heading, preview, cropButton, fitButton, hint, colorRow, transparentButton], spacing: 8)
        sidebar.setCustomSpacing(18, after: preview)
        sidebar.setCustomSpacing(16, after: hint)
        canvas.onCropChange = { [weak self] crop in
            guard let self, self.image != nil else { return }
            self.selections[self.index].crop = crop
            self.preview.display(image: self.image, crop: crop, backgroundColor: self.selections[self.index].output.backgroundColor)
        }

        let cancel = NSButton(title: L("取消"), target: self, action: #selector(cancelEditing))
        cancel.keyEquivalent = "\u{1b}"
        previous.target = self; previous.action = #selector(previousImage)
        advance.target = self; advance.action = #selector(advanceOrExport)
        advance.keyEquivalent = "\r"
        let actions = stack([cancel, previous, advance], vertical: false, spacing: 8)
        previous.isHidden = urls.count == 1

        for view in [filename, position, canvas, sidebar, actions] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            filename.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            filename.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            filename.trailingAnchor.constraint(lessThanOrEqualTo: position.leadingAnchor, constant: -10),
            position.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            position.centerYAnchor.constraint(equalTo: filename.centerYAnchor),
            canvas.leadingAnchor.constraint(equalTo: filename.leadingAnchor),
            canvas.topAnchor.constraint(equalTo: filename.bottomAnchor, constant: 12),
            canvas.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: -20),
            canvas.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -16),
            sidebar.topAnchor.constraint(equalTo: canvas.topAnchor),
            sidebar.trailingAnchor.constraint(equalTo: position.trailingAnchor),
            sidebar.bottomAnchor.constraint(lessThanOrEqualTo: canvas.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 196),
            colorWell.widthAnchor.constraint(equalToConstant: 68),
            hint.widthAnchor.constraint(equalTo: sidebar.widthAnchor),
            preview.widthAnchor.constraint(equalToConstant: 148),
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor),
            actions.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
    }

    private func loadCurrent() {
        colorWell.deactivate()
        let id = UUID(), url = urls[index]
        loadID = id
        image = nil
        filename.stringValue = url.lastPathComponent
        filename.toolTip = url.lastPathComponent
        position.stringValue = urls.count > 1 ? "\(index + 1) / \(urls.count)" : ""
        previous.isEnabled = index > 0
        advance.title = index < urls.count - 1 ? L("下一张") : (urls.count == 1 ? L("生成图标") : L("全部生成"))
        refresh()
        hint.stringValue = L("正在载入预览…")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try MediaTools.iconPreview(url) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadID == id else { return }
                switch result {
                case .success(let image):
                    self.image = image
                    self.refresh()
                case .failure(let error):
                    self.hint.stringValue = error.localizedDescription
                }
            }
        }
    }

    private func refresh() {
        let selection = selections[index]
        cropButton.state = selection.keepsWholeImage ? .off : .on
        fitButton.state = selection.keepsWholeImage ? .on : .off
        for control in [cropButton, fitButton, advance, transparentButton, colorWell] as [NSControl] {
            control.isEnabled = image != nil
        }
        transparentButton.state = selection.isTransparent ? .on : .off
        if colorWell.color != selection.color { colorWell.color = selection.color }
        let options = selection.output
        canvas.display(image: image, crop: options.crop, backgroundColor: options.backgroundColor)
        preview.display(image: image, crop: options.crop, backgroundColor: options.backgroundColor)
        hint.stringValue = selection.keepsWholeImage ? L("整张图片会等比缩放并居中。") : L("拖动方框移动裁剪区域，拖动四角调整大小。")
    }

    @objc private func changeMode(_ sender: NSButton) {
        selections[index].keepsWholeImage = sender === fitButton
        refresh()
    }
    @objc private func changeColor() {
        guard image != nil, let color = colorWell.color.usingColorSpace(.sRGB) else { return }
        selections[index].color = color.withAlphaComponent(1)
        selections[index].isTransparent = false
        refresh()
    }
    @objc private func changeTransparency() {
        selections[index].isTransparent = transparentButton.state == .on
        refresh()
    }
    @objc private func cancelEditing() { close() }
    @objc private func previousImage() {
        guard index > 0 else { return }
        index -= 1
        loadCurrent()
    }
    @objc private func advanceOrExport() {
        guard image != nil else { return }
        if index < urls.count - 1 {
            index += 1
            loadCurrent()
            return
        }
        var options = [URL: IconExportOptions]()
        for (url, selection) in zip(urls, selections) { options[url] = selection.output }
        close()
        export(options)
    }

    func windowWillClose(_ notification: Notification) {
        loadID = UUID()
        colorWell.deactivate()
        onClose?()
    }
}
