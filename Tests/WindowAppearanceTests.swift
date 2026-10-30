import AppKit
import XCTest
@testable import Crab

@MainActor
final class WindowAppearanceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Crab-WindowAppearance-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func window() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    func testExplicitThemesAffectOnlyTheRequestedWindowAndLeaveTheMenuBarOnTheSystemAppearance() throws {
        let originalApplicationAppearance = NSApp.appearance?.name
        let originalEffectiveAppearance = NSApp.effectiveAppearance.name
        let first = window(), second = window()
        defer { first.close(); second.close() }
        for (theme, expected) in [(WindowTheme.light, NSAppearance.Name.aqua), (.dark, .darkAqua)] {
            WindowAppearance.apply(to: first, theme: theme)
            XCTAssertEqual(first.appearance?.name, expected)
            XCTAssertEqual(first.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            XCTAssertNil(second.appearance)
            XCTAssertEqual(NSApp.appearance?.name, originalApplicationAppearance)
            XCTAssertEqual(NSApp.effectiveAppearance.name, originalEffectiveAppearance)
            XCTAssertTrue(try XCTUnwrap(StatusBarPresentation.icon()).isTemplate)
        }
        WindowAppearance.apply(to: first, theme: .system)
        XCTAssertNil(first.appearance)
        XCTAssertEqual(first.effectiveAppearance.name, originalEffectiveAppearance)
    }

    func testBoundWindowsFollowTheirOwnStoreAndCanReturnToSystemAppearance() {
        let firstStore = ConfigurationStore(directory: directory.appendingPathComponent("first"))
        let secondStore = ConfigurationStore(directory: directory.appendingPathComponent("second"))
        firstStore.update { $0.windowTheme = .dark }
        secondStore.update { $0.windowTheme = .light }
        let first = window(), second = window()
        defer { first.close(); second.close() }
        WindowAppearance.bind(first, to: firstStore)
        WindowAppearance.bind(second, to: secondStore)
        XCTAssertEqual(first.appearance?.name, .darkAqua)
        XCTAssertEqual(second.appearance?.name, .aqua)
        firstStore.update { $0.windowTheme = .light }
        XCTAssertEqual(first.appearance?.name, .aqua)
        XCTAssertEqual(second.appearance?.name, .aqua)
        secondStore.update { $0.windowTheme = .dark }
        XCTAssertEqual(first.appearance?.name, .aqua)
        XCTAssertEqual(second.appearance?.name, .darkAqua)
        firstStore.update { $0.windowTheme = .system }
        XCTAssertNil(first.appearance)
        XCTAssertEqual(second.appearance?.name, .darkAqua)
    }

    func testWindowBindingsReleaseTheirTemporaryStoreWhenTheWindowIsReleased() {
        weak var releasedStore: ConfigurationStore?
        autoreleasepool {
            var store: ConfigurationStore? = ConfigurationStore(directory: directory.appendingPathComponent("release"))
            var scene: NSWindow? = window()
            releasedStore = store
            WindowAppearance.bind(scene!, to: store!)
            scene?.close()
            scene = nil
            store = nil
        }
        XCTAssertNil(releasedStore)
    }

    func testExistingAndNewToolWindowsUseTheInjectedWindowTheme() throws {
        let store = ConfigurationStore(directory: directory.appendingPathComponent("tools"))
        store.update { $0.windowTheme = .dark }
        let text = TextWindowController(title: "Test", text: "Test", store: store)
        let repair = FilenameRepairWindowController(urls: [], store: store)
        defer { text.window?.close(); repair.window?.close() }
        XCTAssertEqual(try XCTUnwrap(text.window).appearance?.name, .darkAqua)
        XCTAssertEqual(try XCTUnwrap(repair.window).appearance?.name, .darkAqua)
        store.update { $0.windowTheme = .light }
        XCTAssertEqual(text.window?.appearance?.name, .aqua)
        XCTAssertEqual(repair.window?.appearance?.name, .aqua)
        let later = TextWindowController(title: "Later", text: "Later", store: store)
        defer { later.window?.close() }
        XCTAssertEqual(try XCTUnwrap(later.window).appearance?.name, .aqua)
        XCTAssertFalse(text.window!.isVisible)
        XCTAssertFalse(repair.window!.isVisible)
        XCTAssertFalse(later.window!.isVisible)
    }

    func testErrorAlertsFollowTheOwningStoreWithoutChangingApplicationAppearance() {
        let store = ConfigurationStore(directory: directory.appendingPathComponent("error-alert"))
        store.update { $0.windowTheme = .light }
        let applicationAppearance = NSApp.appearance
        let alert = WindowAppearance.errorAlert(CocoaError(.fileReadUnknown), store: store)
        defer { alert.window.close() }
        XCTAssertEqual(alert.window.appearance?.name, .aqua)
        store.update { $0.windowTheme = .dark }
        XCTAssertEqual(alert.window.appearance?.name, .darkAqua)
        XCTAssertTrue(NSApp.appearance === applicationAppearance)
        XCTAssertFalse(alert.window.isVisible)
    }

    func testSettingsMaterialCardsUseOnlyATranslucentOverlayAndClipRoundedContents() throws {
        let scene = window()
        defer { scene.close() }
        let card = ReferenceMaterialCard(frame: NSRect(x: 10, y: 10, width: 160, height: 90))
        scene.contentView?.addSubview(card)
        card.layoutSubtreeIfNeeded()

        XCTAssertFalse((card as NSView) is NSVisualEffectView, "A nested content-background effect must not cover the existing window material.")
        XCTAssertFalse(card.isOpaque)
        XCTAssertTrue(card.isFlipped)
        XCTAssertTrue(card.wantsDefaultClipping)
        XCTAssertEqual(try XCTUnwrap(card.layer).cornerRadius, 16)
        XCTAssertTrue(try XCTUnwrap(card.layer).masksToBounds)
        XCTAssertNil(card.layer?.backgroundColor, "Do not cover the window material with a solid layer color.")
        XCTAssertEqual(card.alphaValue, 1, "Transparency belongs to the background tint; child controls must remain opaque.")

        card.setFrameSize(NSSize(width: 150, height: 80))
        card.layoutSubtreeIfNeeded()
        XCTAssertEqual(card.bounds.size, NSSize(width: 150, height: 80))
        XCTAssertTrue(try XCTUnwrap(card.layer).masksToBounds)
    }

    func testSettingsMaterialCardsInheritThemeChangesWithoutTheirOwnAppearanceOverride() {
        let scene = window()
        defer { scene.close() }
        let card = ReferenceMaterialCard(frame: NSRect(x: 10, y: 10, width: 160, height: 90))
        scene.contentView?.addSubview(card)
        let applicationAppearance = NSApp.appearance
        for (theme, expected) in [(WindowTheme.light, NSAppearance.Name.aqua), (.dark, .darkAqua)] {
            WindowAppearance.apply(to: scene, theme: theme)
            XCTAssertNil(card.appearance)
            XCTAssertEqual(card.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            XCTAssertFalse(card.isOpaque)
        }
        WindowAppearance.apply(to: scene, theme: .system)
        XCTAssertNil(card.appearance)
        XCTAssertEqual(card.effectiveAppearance.name, scene.effectiveAppearance.name)
        XCTAssertTrue(NSApp.appearance === applicationAppearance)
        XCTAssertFalse(scene.isVisible)
    }

    func testSettingsMaterialCardPixelsRetainTheColoredBackdropInBothThemes() throws {
        let scene = window()
        defer { scene.close() }
        let backdrop = MaterialTestGradient(frame: NSRect(x: 0, y: 0, width: 180, height: 120))
        scene.contentView = backdrop
        let card = ReferenceMaterialCard(frame: NSRect(x: 10, y: 10, width: 160, height: 100))
        backdrop.addSubview(card)

        func capture() throws -> NSBitmapImageRep {
            backdrop.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
            backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
            return bitmap
        }
        func sample(_ bitmap: NSBitmapImageRep, _ x: CGFloat) throws -> NSColor {
            let px = Int(x / backdrop.bounds.width * CGFloat(bitmap.pixelsWide))
            return try XCTUnwrap(bitmap.colorAt(x: px, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        }
        for theme in [WindowTheme.light, .dark] {
            WindowAppearance.apply(to: scene, theme: theme)
            card.isHidden = true
            let plain = try capture()
            card.isHidden = false
            card.needsDisplay = true
            let tinted = try capture()
            let leftPlain = try sample(plain, 35), rightPlain = try sample(plain, 145)
            let leftTinted = try sample(tinted, 35), rightTinted = try sample(tinted, 145)
            let originalVariation = abs(leftPlain.redComponent - rightPlain.redComponent) + abs(leftPlain.blueComponent - rightPlain.blueComponent)
            let retainedVariation = abs(leftTinted.redComponent - rightTinted.redComponent) + abs(leftTinted.blueComponent - rightTinted.blueComponent)
            XCTAssertGreaterThan(originalVariation, 0.5, theme.rawValue)
            XCTAssertGreaterThan(retainedVariation, originalVariation * 0.7, theme.rawValue)
            XCTAssertLessThan(retainedVariation, originalVariation * 0.95, "The actual tint must be drawn, rather than leaving the background untouched.")
            let tintChange = abs(leftTinted.redComponent - leftPlain.redComponent) + abs(leftTinted.greenComponent - leftPlain.greenComponent) + abs(leftTinted.blueComponent - leftPlain.blueComponent)
            XCTAssertGreaterThan(tintChange, 0.03, theme.rawValue)
            XCTAssertLessThan(tintChange, 0.5, theme.rawValue)
        }
        XCTAssertFalse(scene.isVisible)
    }

    func testSettingsMaterialCardHasAGentleGradientEvenOverAFlatBackdrop() throws {
        let scene = window()
        defer { scene.close() }
        let backdrop = MaterialTestFlatBackdrop(frame: NSRect(x: 0, y: 0, width: 180, height: 120))
        scene.contentView = backdrop
        let card = ReferenceMaterialCard(frame: NSRect(x: 10, y: 10, width: 160, height: 100))
        backdrop.addSubview(card)
        let applicationAppearance = NSApp.appearance

        for theme in [WindowTheme.light, .dark] {
            WindowAppearance.apply(to: scene, theme: theme)
            card.needsDisplay = true
            backdrop.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
            backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
            func level(at x: CGFloat) throws -> CGFloat {
                let px = Int(x / backdrop.bounds.width * CGFloat(bitmap.pixelsWide))
                let color = try XCTUnwrap(bitmap.colorAt(x: px, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
                return (color.redComponent + color.greenComponent + color.blueComponent) / 3
            }
            let left = try level(at: 35), right = try level(at: 145)
            let difference = abs(left - right)
            XCTAssertGreaterThan(difference, 0.02, "The card must not become a flat solid fill over a uniform background.")
            XCTAssertLessThan(difference, 0.12, "Keep the gradient subtle enough for the settings controls.")
            if theme == .light { XCTAssertGreaterThan(left, right) }
            else { XCTAssertLessThan(left, right) }
            XCTAssertEqual(card.alphaValue, 1, "Controls inherit full opacity; only the drawn background is translucent.")
        }
        XCTAssertTrue(NSApp.appearance === applicationAppearance)
        XCTAssertFalse(scene.isVisible)
    }

    func testLibrarySearchFieldRetainsItsBackdropAndFollowsTheWindowTheme() throws {
        let scene = window()
        defer { scene.close() }
        let backdrop = MaterialTestGradient(frame: NSRect(x: 0, y: 0, width: 180, height: 120))
        scene.contentView = backdrop
        let field = OperationLibrarySearchField(frame: NSRect(x: 10, y: 48, width: 160, height: 24))
        field.controlSize = .small; field.font = .systemFont(ofSize: 12)
        field.stringValue = ""; field.placeholderString = ""
        backdrop.addSubview(field)
        let applicationAppearance = NSApp.appearance
        XCTAssertFalse(field.drawsBackground)
        XCTAssertTrue(field.isBezeled)
        XCTAssertFalse(field.isOpaque)
        XCTAssertEqual(field.alphaValue, 1)
        XCTAssertEqual(field.focusRingType, .default)
        let focusMask = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 24,
                                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let focusContext = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: focusMask))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = focusContext
        focusContext.cgContext.clear(field.bounds)
        field.cell?.drawFocusRingMask(withFrame: field.bounds, in: field)
        NSGraphicsContext.restoreGraphicsState()
        XCTAssertLessThan(try XCTUnwrap(focusMask.colorAt(x: 0, y: 0)).alphaComponent, 0.05, "The focus ring must follow rounded corners.")
        XCTAssertGreaterThan(try XCTUnwrap(focusMask.colorAt(x: 80, y: 12)).alphaComponent, 0.95)

        func capture() throws -> NSBitmapImageRep {
            backdrop.needsDisplay = true; field.needsDisplay = true
            backdrop.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
            backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
            return bitmap
        }
        func sample(_ bitmap: NSBitmapImageRep, at x: CGFloat) throws -> NSColor {
            let px = Int(x / backdrop.bounds.width * CGFloat(bitmap.pixelsWide))
            return try XCTUnwrap(bitmap.colorAt(x: px, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        }
        var themeSamples: [NSColor] = []
        for (theme, expected) in [(WindowTheme.light, NSAppearance.Name.aqua), (.dark, .darkAqua)] {
            field.stringValue = ""; field.placeholderString = ""
            WindowAppearance.apply(to: scene, theme: theme)
            XCTAssertNil(field.appearance)
            XCTAssertEqual(field.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            field.isHidden = true
            let plain = try capture()
            field.isHidden = false
            let tinted = try capture()
            let leftPlain = try sample(plain, at: 55), rightPlain = try sample(plain, at: 125)
            let leftTinted = try sample(tinted, at: 55), rightTinted = try sample(tinted, at: 125)
            let originalVariation = abs(leftPlain.redComponent - rightPlain.redComponent) + abs(leftPlain.blueComponent - rightPlain.blueComponent)
            let retainedVariation = abs(leftTinted.redComponent - rightTinted.redComponent) + abs(leftTinted.blueComponent - rightTinted.blueComponent)
            XCTAssertGreaterThan(originalVariation, 0.4, theme.rawValue)
            XCTAssertGreaterThan(retainedVariation, originalVariation * 0.65, "An opaque input must not erase the window material.")
            let tintChange = abs(leftTinted.redComponent - leftPlain.redComponent) + abs(leftTinted.greenComponent - leftPlain.greenComponent) + abs(leftTinted.blueComponent - leftPlain.blueComponent)
            XCTAssertGreaterThan(tintChange, 0.03, "The translucent input tint must actually be drawn.")
            XCTAssertLessThan(tintChange, 0.5, theme.rawValue)
            themeSamples.append(leftTinted)

            XCTAssertTrue(scene.makeFirstResponder(field))
            field.selectText(nil)
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView, "Use AppKit's real field editor in the offscreen window.")
            XCTAssertTrue(scene.firstResponder === editor)
            XCTAssertTrue(editor.window === scene)
            XCTAssertTrue(editor.isFieldEditor)
            XCTAssertFalse(editor.drawsBackground, "Editing must not replace the input tint with an opaque background.")
            XCTAssertFalse(editor.isOpaque)
            let cell = try XCTUnwrap(field.cell as? NSSearchFieldCell)
            let textRect = cell.searchTextRect(forBounds: field.bounds)
            let editorRect = field.convert(editor.bounds, from: editor)
            XCTAssertEqual(cell.drawingRect(forBounds: field.bounds), textRect)
            XCTAssertEqual(cell.titleRect(forBounds: field.bounds), textRect)
            XCTAssertGreaterThanOrEqual(textRect.minX, cell.searchButtonRect(forBounds: field.bounds).maxX - 1)
            XCTAssertGreaterThanOrEqual(editorRect.minX, textRect.minX - 1, "The real editor must not start over the search icon.")
            XCTAssertEqual(textRect.midY, field.bounds.midY, accuracy: 0.5)
            XCTAssertEqual(editorRect.midY, field.bounds.midY, accuracy: 1, "The live editing rect must remain vertically centered.")
            let editing = try capture()
            let leftEditing = try sample(editing, at: 55), rightEditing = try sample(editing, at: 125)
            let editingVariation = abs(leftEditing.redComponent - rightEditing.redComponent) + abs(leftEditing.blueComponent - rightEditing.blueComponent)
            XCTAssertGreaterThan(editingVariation, originalVariation * 0.65, "The real field editor must retain the window's visible background variation.")
            field.placeholderString = "搜索名称或内容"
            func checkEditor(_ current: NSTextView) {
                let visible = field.convert(current.visibleRect, from: current)
                XCTAssertGreaterThanOrEqual(visible.minX, textRect.minX - 1, "Focused text must remain after the search glyph.")
                XCTAssertEqual(visible.midY, editorRect.midY, accuracy: 1)
                XCTAssertEqual(visible.minX, editorRect.minX, accuracy: 1, "Entering or clearing text must not jump to the left edge.")
            }
            checkEditor(editor)
            editor.insertText("Crab", replacementRange: NSRange(location: 0, length: 0))
            XCTAssertEqual(editor.string, "Crab")
            checkEditor(editor)
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count)); editor.deleteBackward(nil)
            XCTAssertEqual(editor.string, "")
            checkEditor(editor)
            XCTAssertTrue(scene.makeFirstResponder(nil))
            XCTAssertNil(field.currentEditor())
            XCTAssertTrue(scene.makeFirstResponder(field)); field.selectText(nil)
            let reentered = try XCTUnwrap(field.currentEditor() as? NSTextView)
            XCTAssertEqual(reentered.string, ""); checkEditor(reentered)
            XCTAssertTrue(scene.makeFirstResponder(nil))
        }
        let light = themeSamples[0], dark = themeSamples[1]
        let themeChange = abs(light.redComponent - dark.redComponent) + abs(light.greenComponent - dark.greenComponent) + abs(light.blueComponent - dark.blueComponent)
        XCTAssertGreaterThan(themeChange, 0.05, "The input tint must update when its owning window changes theme.")
        XCTAssertTrue(NSApp.appearance === applicationAppearance)
        XCTAssertFalse(scene.isVisible)
    }

    func testMonochromeSidebarGlyphHasNoColoredTileAndKeepsItsTemplateArtwork() throws {
        let badge = ReferenceBadge(icon: .customIcons, size: 40)
        badge.appearance = NSAppearance(named: .aqua)
        badge.layoutSubtreeIfNeeded()
        func opaquePixels() throws -> Int {
            let image = try XCTUnwrap(badge.bitmapImageRepForCachingDisplay(in: badge.bounds))
            badge.cacheDisplay(in: badge.bounds, to: image)
            var count = 0
            for y in 0..<image.pixelsHigh {
                for x in 0..<image.pixelsWide where (image.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { count += 1 }
            }
            return count
        }
        let colored = try opaquePixels()
        badge.iconStyle = .monochrome
        let monochrome = try opaquePixels()
        XCTAssertGreaterThan(monochrome, 20)
        XCTAssertGreaterThan(colored, monochrome * 2)
        let imageView = try XCTUnwrap(badge.subviews.compactMap { $0 as? NSImageView }.first)
        XCTAssertTrue(try XCTUnwrap(imageView.image).isTemplate)
        XCTAssertEqual(imageView.contentTintColor, .labelColor)
    }
}

private final class MaterialTestGradient: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.36, blue: 0.88, alpha: 1),
                   ending: NSColor(srgbRed: 0.88, green: 0.54, blue: 0.12, alpha: 1))!
            .draw(in: bounds, angle: 0)
    }
}

private final class MaterialTestFlatBackdrop: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1).setFill()
        bounds.fill()
    }
}
