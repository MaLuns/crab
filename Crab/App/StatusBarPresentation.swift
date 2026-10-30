import AppKit

enum StatusBarPresentation {
    static func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            NSColor.black.setFill()
            NSColor.black.setStroke()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 18, height: 18),
                         xRadius: 3.2, yRadius: 3.2).fill()
            context.saveGState()
            context.setBlendMode(.destinationOut)
            context.translateBy(x: 1.2, y: 1.8)
            context.scaleBy(x: 0.78, y: 0.78)

            func drawSide() {
                let claw = NSBezierPath()
                claw.move(to: NSPoint(x: 3.5, y: 10.2))
                claw.curve(to: NSPoint(x: 1.8, y: 14.8),
                           controlPoint1: NSPoint(x: 1.5, y: 11.1), controlPoint2: NSPoint(x: 0.9, y: 13.1))
                claw.curve(to: NSPoint(x: 2.5, y: 14.7),
                           controlPoint1: NSPoint(x: 2.0, y: 15.2), controlPoint2: NSPoint(x: 2.5, y: 15.1))
                claw.line(to: NSPoint(x: 2.6, y: 13.3))
                claw.curve(to: NSPoint(x: 4.4, y: 15.2),
                           controlPoint1: NSPoint(x: 3.6, y: 13.7), controlPoint2: NSPoint(x: 4.2, y: 14.5))
                claw.curve(to: NSPoint(x: 5.0, y: 15.2),
                           controlPoint1: NSPoint(x: 4.5, y: 15.6), controlPoint2: NSPoint(x: 4.9, y: 15.6))
                claw.curve(to: NSPoint(x: 3.5, y: 10.2),
                           controlPoint1: NSPoint(x: 5.7, y: 13.0), controlPoint2: NSPoint(x: 5.0, y: 11.0))
                claw.close()
                claw.fill()

                let limbs = NSBezierPath()
                limbs.lineWidth = 1.5
                limbs.lineCapStyle = .round
                limbs.lineJoinStyle = .round
                limbs.move(to: NSPoint(x: 6.7, y: 9.2))
                limbs.curve(to: NSPoint(x: 3.6, y: 11.0),
                            controlPoint1: NSPoint(x: 4.8, y: 9.0), controlPoint2: NSPoint(x: 3.7, y: 9.6))
                for points: [NSPoint] in [
                    [.init(x: 6.6, y: 8.0), .init(x: 3.5, y: 7.3), .init(x: 2.1, y: 5.6)],
                    [.init(x: 6.5, y: 6.5), .init(x: 4.4, y: 5.2), .init(x: 3.4, y: 3.6)],
                    [.init(x: 7.6, y: 5.1), .init(x: 6.4, y: 3.6), .init(x: 5.9, y: 2.6)]
                ] {
                    limbs.move(to: points[0]); limbs.line(to: points[1]); limbs.line(to: points[2])
                }
                limbs.stroke()
            }

            drawSide()
            context.saveGState()
            context.translateBy(x: 20, y: 0)
            context.scaleBy(x: -1, y: 1)
            drawSide()
            context.restoreGState()

            NSBezierPath(roundedRect: NSRect(x: 5.8, y: 4.6, width: 8.4, height: 6.5),
                         xRadius: 3.2, yRadius: 3.2).fill()
            let eyes = NSBezierPath()
            eyes.lineWidth = 1.4; eyes.lineCapStyle = .round
            for x: CGFloat in [8.1, 11.9] {
                eyes.move(to: NSPoint(x: x, y: 10.5)); eyes.line(to: NSPoint(x: x, y: 12.2))
            }
            eyes.stroke()
            context.restoreGState()
            context.endTransparencyLayer()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Crab"
        return image
    }

    static func menu(target: AnyObject, settingsAction: Selector, quitAction: Selector) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L("通用设置"), action: settingsAction, keyEquivalent: ",").target = target
        let quit = menu.addItem(withTitle: L("退出"), action: quitAction, keyEquivalent: "q")
        quit.target = target
        quit.image = nil
        return menu
    }
}
