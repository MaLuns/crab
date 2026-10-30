import CoreGraphics

enum CrabSymbolArtwork {
    static let names = """
    app-unavailable app-window apps archive arrow-back-up arrow-down arrow-right arrow-up arrow-up-right arrows-move
    book braces brand-apple brand-appstore brand-google brand-javascript brand-lua brand-php brand-python
    brand-ruby brand-swift brand-typescript brand-vscode brand-wechat broadcast
    calendar chart-bar chart-pie check chevron-down chevron-left chevron-right chevron-up chevrons-left
    chevrons-right click clipboard clipboard-copy cloud code copy cut database device-desktop device-laptop
    dots dots-vertical download eraser external-link eye eye-off file file-code file-description file-info
    file-plus file-text file-type-csv file-type-docx file-type-html file-type-jpg file-type-js file-type-pdf
    file-type-png file-type-ppt file-type-svg file-type-txt file-type-xls file-type-xml file-typography
    file-zip files folder folder-cog folder-down folder-minus folder-open folder-plus folder-share
    folder-symlink folder-up folder-x folders git-branch heart heart-plus help-circle info-circle key
    language link lock-open logout mail markdown menu-2 message-circle minus mouse movie music palette
    photo photo-edit photo-scan player-play plus pointer presentation puzzle qrcode refresh rocket rotate
    rotate-clockwise scan screenshot script-applescript script-perl script-shell send settings star table terminal tools trash trash-x upload users
    users-group video wand x
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    static func draw(_ name: String, on c: CrabSymbolCanvas) -> Bool {
        switch name {
        case "settings":
            for (y, x): (CGFloat, CGFloat) in [(6, 8), (12, 16), (18, 10)] {
                c.stroke([(4, y), (x - 2, y)])
                c.stroke([(x + 2, y), (20, y)])
                c.ellipse(x - 2, y - 2, 4, 4)
            }
        case "file-plus":
            path(c) { p in
                p.move(14, 20); p.line(7, 20); p.curve(5.4, 20, 4.5, 19, 4.5, 17.5)
                p.line(4.5, 5.5); p.curve(4.5, 4, 5.4, 3, 7, 3)
                p.line(12.5, 3); p.line(18.5, 9); p.line(18.5, 12)
                p.move(12.5, 3.5); p.line(12.5, 7); p.curve(12.5, 8.5, 13, 9, 14.5, 9); p.line(18, 9)
            }
            plus(c, x: 18, y: 17.5, arm: 3)
        case "copy":
            path(c) { p in
                p.move(6.5, 15); p.line(6, 15); p.curve(4.5, 15, 3.5, 14, 3.5, 12.5)
                p.line(3.5, 5.5); p.curve(3.5, 4, 4.5, 3, 6, 3); p.line(13, 3)
                p.curve(14.5, 3, 15.5, 4, 15.5, 5.5)
            }
            c.roundedRect(8.5, 8, 12, 13, 2.5)
        case "folder", "folder-open", "folder-plus", "folder-minus", "folder-x", "folder-up", "folder-down", "folder-share", "folder-symlink", "folder-cog":
            folder(c)
            switch name {
            case "folder-plus": plus(c, x: 12, y: 14, arm: 2.5)
            case "folder-minus": c.stroke([(9, 14), (15, 14)])
            case "folder-x": cross(c, x: 12, y: 14, arm: 2.3)
            case "folder-up": smallArrow(c, upward: true)
            case "folder-down": smallArrow(c, upward: false)
            case "folder-share":
                c.stroke([(8, 15.5), (14.5, 11.5), (17, 14)])
                c.stroke([(11.5, 11.5), (14.5, 11.5), (14.5, 14.5)])
            case "folder-symlink":
                c.stroke([(7.5, 14), (16.5, 14)])
                c.stroke([(13, 10.5), (16.5, 14), (13, 17.5)])
            case "folder-cog":
                c.ellipse(9.5, 11.5, 5, 5)
                for (a, b) in [((12.0, 10.0), (12.0, 11.5)), ((12.0, 16.5), (12.0, 18.0)),
                               ((8.0, 14.0), (9.5, 14.0)), ((14.5, 14.0), (16.0, 14.0))] {
                    c.stroke([(a.0, a.1), (b.0, b.1)])
                }
            case "folder-open": c.stroke([(6.5, 11.5), (17.5, 11.5)])
            default: break
            }
        case "heart", "heart-plus":
            heart(c)
            if name == "heart-plus" { plus(c, x: 18.5, y: 18, arm: 2.5) }
        case "palette":
            path(c) { p in
                p.move(19.5, 14.5)
                p.curve(17.8, 15.5, 15.5, 13.9, 14.4, 15.1)
                p.curve(13, 16.5, 16.4, 19.7, 13.2, 20.5)
                p.curve(7.8, 22, 3, 17.9, 3, 12.4)
                p.curve(3, 6.9, 7.4, 3.2, 12.6, 3.2)
                p.curve(17.5, 3.2, 21.1, 6.5, 21, 10.3)
                p.curve(21, 12.1, 20.7, 13.6, 19.5, 14.5); p.close()
            }
            c.dot(7.4, 11, 1); c.dot(10.3, 7.3, 1); c.dot(15.1, 7.4, 1)
        case "tools":
            path(c) { p in
                p.move(14.5, 4); p.curve(12.7, 3.1, 10.7, 3.8, 10, 5.5)
                p.curve(9.3, 7.2, 9.7, 8.4, 10.7, 9.5)
                p.line(4.2, 16); p.curve(3.4, 16.8, 3.4, 18.1, 4.2, 18.9)
                p.curve(5, 19.7, 6.3, 19.7, 7.1, 18.9); p.line(13.5, 12.5)
                p.curve(16.3, 13.5, 19.1, 11.8, 19.2, 9)
                p.line(15.9, 9.8); p.line(13.4, 7.3); p.line(14.5, 4); p.close()
            }
            c.stroke([(15.8, 15.6), (19.8, 19.6)])
        case "terminal":
            c.roundedRect(3, 4.5, 18, 15, 3)
            c.stroke([(7, 9), (10.5, 12), (7, 15)])
            c.stroke([(13.5, 15), (17, 15)])
        case "script-shell":
            c.roundedRect(3, 4.5, 18, 15, 3)
            path(c) { p in
                p.move(11.5, 9); p.curve(9.4, 7.4, 6.8, 8.2, 6.8, 10.2)
                p.curve(6.8, 12.5, 11.5, 11.5, 11.5, 13.9)
                p.curve(11.5, 15.9, 8.9, 16.6, 6.8, 15)
            }
            c.stroke([(9.2, 7), (9.2, 17)])
            c.stroke([(15, 15.5), (18, 15.5)])
        case "script-perl":
            path(c) { p in
                p.move(12, 5.5); p.curve(10.5, 8, 4.5, 9.1, 4.5, 14.2)
                p.curve(4.5, 18, 7.5, 20.5, 12, 20.5)
                p.curve(16.5, 20.5, 19.5, 18, 19.5, 14.2)
                p.curve(19.5, 9.1, 13.5, 8, 12, 5.5); p.close()
                p.move(12, 8); p.curve(10.7, 10.4, 8.3, 11.4, 8.3, 14.5)
                p.curve(8.3, 17.2, 9.7, 19.2, 12, 20.5)
                p.move(12, 8); p.curve(13.3, 10.4, 15.7, 11.4, 15.7, 14.5)
                p.curve(15.7, 17.2, 14.3, 19.2, 12, 20.5)
            }
            c.stroke([(10, 3.5), (12, 5.5), (14, 3.5)])
        case "script-applescript":
            path(c) { p in
                p.move(15.5, 5); p.line(7, 5); p.curve(4.5, 5, 3.5, 6.5, 3.5, 8.5)
                p.line(3.5, 10); p.line(7, 10)
                p.move(7, 8); p.line(7, 18); p.curve(7, 19.8, 8.5, 20.5, 10, 20.5)
                p.line(17, 20.5); p.curve(19, 20.5, 20.5, 19.2, 20.5, 17.5)
                p.line(20.5, 16); p.line(10.5, 16); p.line(10.5, 17.5)
                p.curve(10.5, 19.3, 9.8, 20.5, 9, 20.5)
                p.move(17, 10); p.line(17, 16)
                p.move(18, 6.3); p.curve(17.6, 4.2, 18.7, 2.8, 20.5, 2.8)
                p.curve(20.8, 4.7, 19.8, 6, 18, 6.3); p.close()
            }
            c.stroke([(10, 9), (13.5, 9)]); c.stroke([(10, 12.5), (14, 12.5)])
        case "photo", "photo-edit", "photo-scan":
            photo(c, editing: name == "photo-edit")
            if name == "photo-scan" { c.stroke([(6, 15), (18, 15)]) }
        case "app-unavailable":
            path(c) { p in
                p.move(11.5, 18.5); p.line(6.5, 18.5)
                p.curve(4.8, 18.5, 3.5, 17.2, 3.5, 15.5); p.line(3.5, 7)
                p.curve(3.5, 5.3, 4.8, 4, 6.5, 4); p.line(16.5, 4)
                p.curve(18.2, 4, 19.5, 5.3, 19.5, 7); p.line(19.5, 11)
            }
            c.stroke([(3.8, 9), (19.2, 9)])
            c.dot(6.7, 6.5, 0.7)
            c.ellipse(13.5, 13.5, 7, 7)
            c.stroke([(15.5, 17), (18.5, 17)])
        case "app-window":
            c.roundedRect(3.5, 4, 17, 16, 3)
            c.stroke([(3.8, 9), (20.2, 9)])
            c.stroke([(9, 9), (9, 19.5)])
            c.dot(6.7, 6.5, 0.7)
        case "archive":
            c.roundedRect(3.5, 3.5, 17, 5, 1.5)
            path(c) { p in
                p.move(5, 9); p.line(5, 18); p.curve(5, 19.5, 6, 20.5, 7.5, 20.5)
                p.line(16.5, 20.5); p.curve(18, 20.5, 19, 19.5, 19, 18); p.line(19, 9)
            }
            c.stroke([(9, 12.5), (15, 12.5)])
        case "rocket":
            path(c) { p in
                p.move(9, 16); p.curve(8, 10, 12.4, 4.2, 19.5, 3.3)
                p.curve(20, 10.5, 16.4, 15.2, 11, 17); p.close()
                p.move(8.7, 10); p.line(5.2, 10.7); p.line(3.7, 15.2); p.line(8.8, 14)
                p.move(14, 16.1); p.line(13.3, 19.5); p.line(8.8, 21); p.line(10, 17)
            }
            c.ellipse(13.3, 7.1, 3.5, 3.5)
            c.stroke([(6.5, 17.5), (4, 20)])
        case "cloud":
            path(c) { p in
                p.move(7, 19); p.curve(4.7, 19, 3, 17.5, 3, 15)
                p.curve(3, 12.8, 4.5, 11, 6.5, 10.7)
                p.curve(6.6, 6.7, 9.2, 4.4, 12.5, 4.4)
                p.curve(15.8, 4.4, 18, 6.7, 18.4, 9.6)
                p.curve(20.2, 10.1, 21.2, 11.8, 21.2, 14)
                p.curve(21.2, 16.8, 19.5, 19, 16.6, 19); p.line(7, 19); p.close()
            }
        case "key":
            c.ellipse(3.5, 3.5, 10, 10)
            c.dot(8.5, 8.5, 0.85)
            c.stroke([(12, 12), (20.5, 20.5)])
            c.stroke([(17, 17), (19.5, 14.5)])
        case "help-circle":
            c.ellipse(3, 3, 18, 18)
            path(c) { p in
                p.move(9.4, 8.7); p.curve(9.7, 6.2, 14.8, 6.1, 14.8, 9)
                p.curve(14.8, 11.3, 12, 11.1, 12, 13.7)
            }
            c.dot(12, 17, 0.9)
        case "info-circle":
            c.ellipse(3, 3, 18, 18); c.dot(12, 7.5, 0.9)
            c.stroke([(10.5, 11), (12, 11), (12, 17)])
        case "plus": plus(c, x: 12, y: 12, arm: 6.5)
        case "minus": c.stroke([(5.5, 12), (18.5, 12)])
        case "x": cross(c, x: 12, y: 12, arm: 5.3)
        case "check": c.stroke([(4.5, 12), (9.5, 17), (19.5, 6.5)])
        case "arrow-back-up":
            c.stroke([(8.5, 4.5), (3.5, 9.5), (8.5, 14.5)])
            path(c) { p in
                p.move(4, 9.5); p.line(13.5, 9.5); p.curve(17.4, 9.5, 20, 12, 20, 15.5)
                p.line(20, 19)
            }
        case "arrow-right", "arrow-left", "arrow-up", "arrow-down", "arrow-up-right":
            let angle: CGFloat = name == "arrow-up" ? -.pi / 2 : name == "arrow-down" ? .pi / 2
                : name == "arrow-up-right" ? -.pi / 4 : name == "arrow-left" ? .pi : 0
            transformed(c, angle: angle) {
                c.stroke([(4.5, 12), (19.5, 12)])
                c.stroke([(14, 6.5), (19.5, 12), (14, 17.5)])
            }
        case "chevron-right", "chevron-left", "chevron-up", "chevron-down", "chevrons-left", "chevrons-right":
            let angle: CGFloat = name == "chevron-up" ? -.pi / 2 : name == "chevron-down" ? .pi / 2
                : ["chevron-left", "chevrons-left"].contains(name) ? .pi : 0
            transformed(c, angle: angle) {
                if name.hasPrefix("chevrons-") {
                    c.stroke([(6, 6.5), (11.5, 12), (6, 17.5)])
                    c.stroke([(12, 6.5), (17.5, 12), (12, 17.5)])
                } else { c.stroke([(9, 6), (15, 12), (9, 18)]) }
            }
        case "download", "upload":
            c.stroke([(4, 15), (4, 19.5), (20, 19.5), (20, 15)])
            if name == "download" {
                c.stroke([(12, 3), (12, 14.5)])
                c.stroke([(8, 10.5), (12, 14.5), (16, 10.5)])
            } else {
                c.stroke([(12, 15), (12, 3.5)])
                c.stroke([(8, 7.5), (12, 3.5), (16, 7.5)])
            }
        case "external-link":
            path(c) { p in
                p.move(10, 4); p.line(6.5, 4); p.curve(5, 4, 4, 5, 4, 6.5)
                p.line(4, 17.5); p.curve(4, 19, 5, 20, 6.5, 20)
                p.line(17.5, 20); p.curve(19, 20, 20, 19, 20, 17.5); p.line(20, 14)
            }
            c.stroke([(11, 13), (20, 4)]); c.stroke([(13.5, 4), (20, 4), (20, 10.5)])
        case "arrows-move":
            c.stroke([(3, 12), (21, 12)]); c.stroke([(12, 3), (12, 21)])
            c.stroke([(6, 9), (3, 12), (6, 15)]); c.stroke([(18, 9), (21, 12), (18, 15)])
            c.stroke([(9, 6), (12, 3), (15, 6)]); c.stroke([(9, 18), (12, 21), (15, 18)])
        case "refresh", "rotate", "rotate-clockwise":
            let clockwise = name != "rotate"
            if !clockwise { c.context.saveGState(); c.context.translateBy(x: 24, y: 0); c.context.scaleBy(x: -1, y: 1) }
            path(c) { p in
                p.move(5, 8); p.curve(7, 3, 14.4, 2.7, 18.2, 6.8)
                p.line(20, 9); p.move(20, 4); p.line(20, 9); p.line(15, 9)
                p.move(19, 16); p.curve(17, 21, 9.6, 21.3, 5.8, 17.2)
            }
            if name == "refresh" { c.stroke([(4, 20), (4, 15), (9, 15)]) }
            if !clockwise { c.context.restoreGState() }
        case "dots", "dots-vertical":
            for value: CGFloat in [5.5, 12, 18.5] {
                c.dot(name == "dots" ? value : 12, name == "dots" ? 12 : value, 1.35)
            }
        case "menu-2": c.stroke([(4, 6.5), (20, 6.5)]); c.stroke([(4, 12), (20, 12)]); c.stroke([(4, 17.5), (20, 17.5)])
        case "mouse":
            c.roundedRect(6, 3, 12, 18, 6)
            c.stroke([(6.5, 10), (17.5, 10)]); c.stroke([(12, 3.5), (12, 10)])
        case "pointer", "click":
            c.stroke([(4.5, 3.5), (8, 19.5), (11.5, 14), (17, 10.5), (4.5, 3.5)])
            if name == "click" {
                c.stroke([(15.5, 4), (16.5, 2.5)]); c.stroke([(19, 7), (21, 6.5)]); c.stroke([(17, 16), (18.5, 17.5)])
            }
        case "clipboard", "clipboard-copy":
            path(c) { p in
                p.move(8, 5); p.line(6.5, 5); p.curve(5, 5, 4, 6, 4, 7.5)
                p.line(4, 18); p.curve(4, 19.5, 5, 20.5, 6.5, 20.5)
                p.line(17.5, 20.5); p.curve(19, 20.5, 20, 19.5, 20, 18)
                p.line(20, 7.5); p.curve(20, 6, 19, 5, 17.5, 5); p.line(16, 5)
            }
            c.roundedRect(8, 3, 8, 4, 1.5)
            if name == "clipboard-copy" { c.roundedRect(9, 10.5, 6, 6, 1) }
            else { c.stroke([(8, 12), (16, 12)]); c.stroke([(8, 16), (13, 16)]) }
        case "file", "file-code", "file-description", "file-info", "file-text", "file-typography", "file-zip",
             "file-type-csv", "file-type-docx", "file-type-html", "file-type-jpg", "file-type-js", "file-type-pdf",
             "file-type-png", "file-type-ppt", "file-type-svg", "file-type-txt", "file-type-xls", "file-type-xml":
            document(c)
            documentMark(name, on: c)
        case "files":
            c.roundedRect(9, 7, 11.5, 14, 2)
            path(c) { p in
                p.move(5.5, 17); p.curve(4, 17, 3.5, 16, 3.5, 14.5); p.line(3.5, 5.5)
                p.curve(3.5, 4, 4.5, 3, 6, 3); p.line(14, 3)
            }
            c.stroke([(12.5, 11.5), (17, 11.5)]); c.stroke([(12.5, 15.5), (17, 15.5)])
        case "folders":
            path(c) { p in
                p.move(4.5, 15); p.line(4.5, 5.5); p.curve(4.5, 4, 5.5, 3, 7, 3)
                p.line(10.5, 3); p.line(13, 5.5); p.line(18, 5.5)
            }
            c.roundedRect(7.5, 9, 13, 12, 2)
            c.stroke([(8, 13), (20, 13)])
        case "code", "brand-vscode":
            c.stroke([(8, 6), (3, 12), (8, 18)]); c.stroke([(16, 6), (21, 12), (16, 18)])
            c.stroke([(14, 4.5), (10, 19.5)])
            if name == "brand-vscode" { c.stroke([(21, 6), (21, 18)]) }
        case "braces":
            path(c) { p in
                p.move(8.5, 3.5); p.curve(6, 3.5, 6, 4.5, 6, 7.5)
                p.curve(6, 10, 5, 11, 3.5, 12); p.curve(5, 13, 6, 14, 6, 16.5)
                p.curve(6, 19.5, 6, 20.5, 8.5, 20.5)
                p.move(15.5, 3.5); p.curve(18, 3.5, 18, 4.5, 18, 7.5)
                p.curve(18, 10, 19, 11, 20.5, 12); p.curve(19, 13, 18, 14, 18, 16.5)
                p.curve(18, 19.5, 18, 20.5, 15.5, 20.5)
            }
        case "cut":
            c.ellipse(3.5, 14.5, 5.5, 5.5); c.ellipse(15, 14.5, 5.5, 5.5)
            c.stroke([(7.9, 15.7), (18.5, 3.5)]); c.stroke([(16.1, 15.7), (5.5, 3.5)])
        case "eraser":
            c.stroke([(4, 14), (13, 4), (21, 11), (13, 20), (9, 20), (4, 15), (4, 14)])
            c.stroke([(8, 10), (16, 17)]); c.stroke([(13, 20), (21, 20)])
        case "eye", "eye-off":
            path(c) { p in
                p.move(3, 12); p.curve(7.7, 4.5, 16.3, 4.5, 21, 12)
                p.curve(16.3, 19.5, 7.7, 19.5, 3, 12); p.close()
            }
            c.ellipse(9, 9, 6, 6)
            if name == "eye-off" { c.stroke([(4, 3.5), (20, 20.5)]) }
        case "link":
            path(c) { p in
                p.move(9.4, 7.5); p.line(11.7, 5.2); p.curve(16, 0.9, 23.1, 8, 18.8, 12.3); p.line(16.5, 14.6)
                p.move(7.5, 9.4); p.line(5.2, 11.7); p.curve(0.9, 16, 8, 23.1, 12.3, 18.8); p.line(14.6, 16.5)
            }
            c.stroke([(8.5, 15.5), (15.5, 8.5)])
        case "lock-open":
            c.roundedRect(4.5, 10.5, 15, 10, 2.5)
            path(c) { p in
                p.move(8, 10.5); p.line(8, 7); p.curve(8, 2, 15.7, 2, 16, 6.2)
            }
            c.stroke([(12, 14.5), (12, 17)])
        case "trash", "trash-x":
            c.stroke([(3.5, 6.5), (20.5, 6.5)])
            c.stroke([(9, 6), (9, 3.5), (15, 3.5), (15, 6)])
            path(c) { p in
                p.move(5.5, 7); p.line(6.5, 18.5); p.curve(6.6, 20, 7.5, 20.5, 9, 20.5)
                p.line(15, 20.5); p.curve(16.5, 20.5, 17.4, 20, 17.5, 18.5); p.line(18.5, 7)
            }
            if name == "trash-x" { cross(c, x: 12, y: 13.5, arm: 2.4) }
            else { c.stroke([(9.5, 10.5), (10, 16.5)]); c.stroke([(14.5, 10.5), (14, 16.5)]) }
        case "device-desktop", "device-laptop":
            c.roundedRect(3.5, 3.5, 17, 12.5, 2)
            if name == "device-desktop" {
                c.stroke([(12, 16.5), (12, 20.5)]); c.stroke([(7.5, 20.5), (16.5, 20.5)])
            } else { c.stroke([(3.5, 16), (2.5, 20), (21.5, 20), (20.5, 16)]) }
        case "scan", "screenshot":
            scanCorners(c)
            if name == "screenshot" { c.roundedRect(7, 7, 10, 10, 1.5) }
            else { c.stroke([(8, 12), (16, 12)]) }
        case "send":
            c.stroke([(3.5, 4.5), (21, 12), (3.5, 19.5), (7, 12), (3.5, 4.5)])
            c.stroke([(7, 12), (20, 12)])
        case "table":
            c.roundedRect(3.5, 4, 17, 16, 2)
            c.stroke([(4, 9), (20, 9)]); c.stroke([(9.5, 9), (9.5, 19.5)])
            c.stroke([(10, 14.5), (20, 14.5)])
        case "presentation":
            c.roundedRect(3.5, 3.5, 17, 12, 1.5)
            c.stroke([(12, 16), (12, 20.5)]); c.stroke([(8, 20.5), (16, 20.5)])
            c.stroke([(7, 12), (10, 8.5), (13, 10.5), (17, 6.5)])
        case "chart-bar":
            c.stroke([(3.5, 3.5), (3.5, 20.5), (21, 20.5)])
            c.roundedRect(7, 11, 3, 9, 0.8); c.roundedRect(13, 5.5, 3, 14.5, 0.8)
            c.stroke([(20, 15), (20, 20)])
        case "chart-pie":
            path(c) { p in
                p.move(10, 3.5); p.curve(5.8, 4, 3, 7.6, 3, 12)
                p.curve(3, 17, 7, 21, 12, 21); p.curve(16.4, 21, 20, 18.2, 20.5, 14)
                p.line(10, 14); p.close()
                p.move(14, 3); p.curve(18, 3, 21, 6, 21, 10); p.line(14, 10); p.close()
            }
        case "markdown":
            c.roundedRect(2.5, 5, 19, 14, 2)
            c.stroke([(6, 15), (6, 9), (9, 12.5), (12, 9), (12, 15)])
            c.stroke([(17, 9), (17, 15)]); c.stroke([(14.8, 12.8), (17, 15), (19.2, 12.8)])
        case "apps":
            for (x, y): (CGFloat, CGFloat) in [(3.5, 3.5), (13.5, 3.5), (3.5, 13.5), (13.5, 13.5)] {
                c.roundedRect(x, y, 7, 7, 1.8)
            }
        case "book":
            path(c) { p in
                p.move(12, 5.5); p.curve(9.5, 3.5, 6, 3.5, 3.5, 4.5); p.line(3.5, 19)
                p.curve(6.4, 18, 9.5, 18.5, 12, 20.5)
                p.curve(14.5, 18.5, 17.6, 18, 20.5, 19); p.line(20.5, 4.5)
                p.curve(18, 3.5, 14.5, 3.5, 12, 5.5); p.close(); p.move(12, 6); p.line(12, 20)
            }
        case "calendar":
            c.roundedRect(3.5, 5, 17, 15.5, 2.5); c.stroke([(4, 10), (20, 10)])
            c.stroke([(8, 3), (8, 7)]); c.stroke([(16, 3), (16, 7)])
            c.dot(8, 14, 0.85); c.dot(12, 14, 0.85); c.dot(16, 14, 0.85); c.dot(8, 17.5, 0.85)
        case "mail":
            c.roundedRect(3, 5, 18, 14, 2.5)
            c.stroke([(4, 6.5), (12, 13), (20, 6.5)])
        case "music":
            c.stroke([(10, 17), (10, 5), (20, 3.5), (20, 15.5)])
            c.ellipse(4, 15.5, 6, 5); c.ellipse(14, 14, 6, 5)
        case "message-circle":
            path(c) { p in
                p.move(7.5, 19); p.line(3.5, 20.5); p.line(4.6, 16.3)
                p.curve(1.3, 10.5, 5.1, 3.5, 12, 3.5); p.curve(17.2, 3.5, 21, 7, 21, 12)
                p.curve(21, 17, 17.2, 20, 12, 20); p.curve(10.5, 20, 8.8, 19.7, 7.5, 19); p.close()
            }
            c.dot(8, 11.5, 0.85); c.dot(12, 11.5, 0.85); c.dot(16, 11.5, 0.85)
        case "video":
            c.roundedRect(3, 5.5, 12.5, 13, 2.5)
            c.stroke([(15.5, 9), (21, 6), (21, 18), (15.5, 15)])
        case "movie":
            c.roundedRect(3.5, 4, 17, 16, 2)
            c.stroke([(7.5, 4.5), (7.5, 19.5)]); c.stroke([(16.5, 4.5), (16.5, 19.5)])
            for y: CGFloat in [8, 12, 16] { c.stroke([(4, y), (7, y)]); c.stroke([(17, y), (20, y)]) }
        case "player-play": c.stroke([(7, 3.5), (20, 12), (7, 20.5)], closed: true)
        case "star":
            c.stroke([(12, 3), (14.8, 8.8), (21.2, 9.7), (16.6, 14.2), (17.7, 20.6),
                      (12, 17.6), (6.3, 20.6), (7.4, 14.2), (2.8, 9.7), (9.2, 8.8)], closed: true)
        case "users", "users-group":
            c.ellipse(7.5, 3.5, 7, 7)
            path(c) { p in p.move(4.5, 20.5); p.line(4.5, 18); p.curve(4.5, 11.3, 17.5, 11.3, 17.5, 18); p.line(17.5, 20.5) }
            path(c) { p in p.move(18, 5); p.curve(22, 7, 21, 10.5, 18.5, 11.5); p.move(19.5, 14); p.curve(21, 15, 21, 17, 21, 20) }
            if name == "users-group" { c.stroke([(2.5, 15.5), (2.5, 20)]) }
        case "language":
            c.stroke([(3, 6), (14, 6)]); c.stroke([(8.5, 3), (8.5, 6)])
            path(c) { p in p.move(12, 6.5); p.curve(11.2, 12, 7.8, 15.5, 3.5, 17); p.move(5, 9); p.curve(6.5, 12, 9, 14.2, 12, 15.5) }
            c.stroke([(13, 21), (17, 11), (21, 21)]); c.stroke([(14.5, 17.5), (19.5, 17.5)])
        case "database":
            c.ellipse(3.5, 3.5, 17, 6)
            path(c) { p in
                p.move(3.5, 6.5); p.line(3.5, 17.5); p.curve(3.5, 21.5, 20.5, 21.5, 20.5, 17.5); p.line(20.5, 6.5)
                p.move(3.5, 12); p.curve(3.5, 16, 20.5, 16, 20.5, 12)
            }
        case "git-branch":
            c.ellipse(3.5, 3, 5, 5); c.ellipse(15.5, 3, 5, 5); c.ellipse(3.5, 16, 5, 5)
            c.stroke([(6, 8.5), (6, 15.5)])
            path(c) { p in p.move(18, 8.5); p.line(18, 10); p.curve(18, 14.8, 7, 10.5, 6, 15.5) }
        case "broadcast":
            c.dot(12, 18.5, 1.2)
            path(c) { p in
                p.move(8.6, 14.5); p.curve(5.2, 10, 7.2, 6.3, 12, 6.3); p.curve(16.8, 6.3, 18.8, 10, 15.4, 14.5)
                p.move(5.5, 17); p.curve(0.3, 10.3, 4.5, 2.7, 12, 2.7); p.curve(19.5, 2.7, 23.7, 10.3, 18.5, 17)
            }
        case "logout":
            path(c) { p in
                p.move(10, 3.5); p.line(6, 3.5); p.curve(4.5, 3.5, 3.5, 4.5, 3.5, 6)
                p.line(3.5, 18); p.curve(3.5, 19.5, 4.5, 20.5, 6, 20.5); p.line(10, 20.5)
            }
            c.stroke([(10, 12), (21, 12)]); c.stroke([(17, 8), (21, 12), (17, 16)])
        case "qrcode":
            c.roundedRect(3.5, 3.5, 6, 6, 1); c.roundedRect(14.5, 3.5, 6, 6, 1); c.roundedRect(3.5, 14.5, 6, 6, 1)
            c.dot(6.5, 6.5, 0.8); c.dot(17.5, 6.5, 0.8); c.dot(6.5, 17.5, 0.8)
            c.stroke([(14.5, 14.5), (17.5, 14.5), (17.5, 20.5), (20.5, 20.5)])
            c.stroke([(20.5, 14.5), (20.5, 17)]); c.dot(14.5, 20.5, 0.8)
        case "wand":
            c.stroke([(4, 19), (15.5, 7.5), (18.5, 10.5), (7, 22), (4, 19)])
            c.stroke([(13, 10), (16, 13)]); sparkle(c, x: 6, y: 6, arm: 2.8); sparkle(c, x: 18.5, y: 3.5, arm: 1.8)
        case "puzzle":
            path(c) { p in
                p.move(4, 4); p.line(10, 4); p.curve(8, 0.7, 15, 0.7, 13, 4); p.line(20, 4)
                p.line(20, 10); p.curve(16, 8, 16, 15, 20, 13); p.line(20, 20)
                p.line(13, 20); p.curve(15, 16, 8, 16, 10, 20); p.line(4, 20)
                p.line(4, 13); p.curve(0.7, 15, 0.7, 8, 4, 10); p.close()
            }
        case "brand-apple":
            path(c) { p in
                p.move(12, 7); p.curve(6, 3, 2.5, 9, 5, 15.5); p.curve(7.5, 22.5, 9, 20.5, 12, 19.5)
                p.curve(15, 21, 17.5, 22, 20, 15.5); p.curve(16, 13.8, 16, 9, 19, 7.5)
                p.curve(16, 4.5, 14, 5.8, 12, 7); p.close()
                p.move(12, 4.5); p.curve(12.5, 2, 14, 2, 15.5, 2.5)
            }
        case "brand-appstore":
            c.roundedRect(3, 3, 18, 18, 4)
            c.stroke([(7, 17), (14.5, 6)]); c.stroke([(9.5, 6), (17, 17)]); c.stroke([(5.5, 14), (18.5, 14)])
        case "brand-google":
            path(c) { p in
                p.move(18, 6); p.curve(12, 0, 3, 4.5, 3, 12); p.curve(3, 17, 7, 21, 12, 21)
                p.curve(17, 21, 21, 17, 21, 12); p.line(12, 12)
            }
        case "brand-javascript", "brand-typescript":
            c.roundedRect(3, 3, 18, 18, 2.5)
            if name == "brand-javascript" {
                path(c) { p in
                    p.move(6, 8); p.line(10, 8); p.line(10, 14.5)
                    p.curve(10, 17.9, 5.5, 18.2, 5.5, 15)
                }
            } else {
                c.stroke([(5.5, 8), (11, 8)]); c.stroke([(8.3, 8), (8.3, 17)])
            }
            path(c) { p in
                p.move(18, 8.6); p.curve(16.4, 7.1, 13, 7.4, 13, 10)
                p.curve(13, 12.8, 18.5, 11.9, 18.5, 14.8)
                p.curve(18.5, 17.7, 14.6, 18.1, 12.7, 16.3)
            }
        case "brand-python":
            for angle: CGFloat in [0, .pi] {
                transformed(c, angle: angle) {
                    path(c) { p in
                        p.move(6.8, 8.5); p.line(6.8, 6.2)
                        p.curve(6.8, 4.5, 7.9, 3.5, 9.7, 3.5); p.line(13.6, 3.5)
                        p.curve(15.5, 3.5, 16.6, 4.6, 16.6, 6.5); p.line(16.6, 8.6)
                        p.curve(16.6, 10.1, 15.3, 10.7, 13.5, 10.7); p.line(10.2, 10.7)
                        p.curve(8.3, 10.7, 7.4, 12.6, 7.4, 14.5); p.line(7.4, 16.8)
                        p.line(5.8, 16.8); p.curve(3.8, 16.8, 3, 15.1, 3, 13)
                        p.line(3, 12); p.curve(3, 9.8, 4.2, 8.5, 6.8, 8.5); p.close()
                        p.move(6.8, 8.5); p.line(10.7, 8.5)
                    }
                    c.dot(9.5, 6.2, 0.6)
                }
            }
        case "brand-ruby":
            c.stroke([(3.5, 9), (7.5, 4.5), (16.5, 4.5), (20.5, 9), (12, 20.5)], closed: true)
            c.stroke([(3.5, 9), (20.5, 9)])
            c.stroke([(7.5, 4.5), (8, 9), (12, 20.5), (16, 9), (16.5, 4.5)])
            c.stroke([(8, 9), (12, 4.5), (16, 9)])
        case "brand-php":
            c.ellipse(2.5, 5, 19, 14)
            c.context.saveGState(); c.context.setLineWidth(1.35)
            for x: CGFloat in [5.2, 15.2] {
                path(c) { p in
                    p.move(x, 16); p.line(x, 9); p.line(x + 1.8, 9)
                    p.curve(x + 4.5, 9, x + 4.5, 13, x + 1.8, 13); p.line(x, 13)
                }
            }
            c.stroke([(10.5, 8.5), (10.5, 15.5)]); c.stroke([(13.3, 8.5), (13.3, 15.5)])
            c.stroke([(10.5, 12), (13.3, 12)])
            c.context.restoreGState()
        case "brand-lua":
            path(c) { p in
                p.move(15.5, 4.5); p.curve(7, 0.8, 1.6, 10.7, 6.7, 17.6)
                p.curve(11.1, 23.4, 19.8, 20.2, 20.5, 13)
                p.curve(17.1, 16, 11.9, 14.7, 11, 10.5)
                p.curve(10.3, 7.5, 12.5, 5.1, 15.5, 4.5); p.close()
            }
            sparkle(c, x: 19.5, y: 5, arm: 1.5)
        case "brand-swift":
            path(c) { p in
                p.move(3, 5.5); p.line(13.5, 13.5); p.line(7, 3); p.line(18.5, 12)
                p.curve(20, 9, 19.5, 6.5, 18.5, 4.5); p.curve(22, 8, 22, 14, 19.5, 17)
                p.line(21, 20); p.line(17, 18.5); p.curve(11.5, 22, 5.5, 18.5, 3.5, 14)
                p.curve(7.5, 17, 10.5, 17, 13.5, 16); p.line(3, 5.5)
            }
        case "brand-wechat":
            path(c) { p in
                p.move(8, 15); p.line(4, 17); p.line(5, 13.5); p.curve(0.5, 8, 4, 3.5, 9.5, 3.5)
                p.curve(13.5, 3.5, 16, 5.7, 16, 8.5)
                p.move(14, 19); p.curve(8, 19, 7, 11, 13, 9); p.curve(19, 7, 24, 13, 19.5, 17)
                p.line(20, 20.5); p.line(17, 19); p.line(14, 19)
            }
            c.dot(7, 8, 0.8); c.dot(11.5, 8, 0.8); c.dot(13.5, 13.5, 0.8); c.dot(17.5, 13.5, 0.8)
        default: return false
        }
        return true
    }

    private static func document(_ c: CrabSymbolCanvas) {
        path(c) { p in
            p.move(13, 3); p.line(7, 3); p.curve(5.5, 3, 4.5, 4, 4.5, 5.5)
            p.line(4.5, 18.5); p.curve(4.5, 20, 5.5, 21, 7, 21)
            p.line(17, 21); p.curve(18.5, 21, 19.5, 20, 19.5, 18.5)
            p.line(19.5, 9.5); p.line(13, 3); p.close()
            p.move(13, 3.5); p.line(13, 7); p.curve(13, 8.5, 14, 9.5, 15.5, 9.5); p.line(19, 9.5)
        }
    }

    private static func documentMark(_ name: String, on c: CrabSymbolCanvas) {
        switch name {
        case "file": break
        case "file-plus": plus(c, x: 12, y: 15, arm: 2.5)
        case "file-code", "file-type-html", "file-type-xml", "file-type-js":
            c.stroke([(10, 12.5), (7.5, 15), (10, 17.5)])
            c.stroke([(14, 12.5), (16.5, 15), (14, 17.5)])
        case "file-typography", "file-type-docx", "file-type-txt":
            c.stroke([(8, 12.5), (16, 12.5)]); c.stroke([(12, 12.5), (12, 18)])
        case "file-text", "file-description":
            c.stroke([(8, 12.5), (16, 12.5)]); c.stroke([(8, 16.5), (13.5, 16.5)])
        case "file-info": c.dot(12, 12, 0.85); c.stroke([(12, 15), (12, 18)])
        case "file-type-csv", "file-type-xls":
            c.roundedRect(8, 12, 8, 6, 0.5); c.stroke([(12, 12), (12, 18)]); c.stroke([(8, 15), (16, 15)])
        case "file-type-jpg", "file-type-png":
            c.stroke([(8, 17.5), (11, 13.5), (13.5, 16.5), (16, 14.5), (16.5, 17.5)])
            c.dot(15.5, 12, 0.7)
        case "file-type-ppt": c.stroke([(9, 18), (9, 12), (15.5, 12), (15.5, 15), (9.5, 15)])
        case "file-type-pdf":
            c.stroke([(8.5, 18), (11.5, 12), (15, 18)])
            c.stroke([(8, 16.5), (16, 16.5)])
        case "file-type-svg":
            c.stroke([(8, 18), (12, 12), (16, 18)], closed: true)
            c.dot(8, 18, 0.65); c.dot(12, 12, 0.65); c.dot(16, 18, 0.65)
        case "file-zip":
            for y: CGFloat in [11.5, 14, 16.5] { c.stroke([(11, y), (13, y + 1)]) }
        default: break
        }
    }

    private static func folder(_ c: CrabSymbolCanvas) {
        path(c) { p in
            p.move(3, 8); p.line(3, 6); p.curve(3, 4.4, 4, 3.5, 5.5, 3.5)
            p.line(9, 3.5); p.line(12, 6.5); p.line(18.5, 6.5)
            p.curve(20, 6.5, 21, 7.5, 21, 9); p.line(21, 17.8)
            p.curve(21, 19.5, 20, 20.5, 18.5, 20.5); p.line(5.5, 20.5)
            p.curve(4, 20.5, 3, 19.5, 3, 17.8); p.line(3, 8); p.close()
            p.move(3.5, 8); p.line(9.5, 8)
        }
    }

    private static func heart(_ c: CrabSymbolCanvas) {
        path(c) { p in
            p.move(12, 20.5); p.curve(10, 18.7, 3.5, 14.5, 3.5, 9)
            p.curve(3.5, 3, 10, 2.5, 12, 7); p.curve(14, 2.5, 20.5, 3, 20.5, 9)
            p.curve(20.5, 14.5, 14, 18.7, 12, 20.5); p.close()
        }
    }

    private static func photo(_ c: CrabSymbolCanvas, editing: Bool) {
        if editing {
            path(c) { p in
                p.move(20.5, 9); p.line(20.5, 7); p.curve(20.5, 5.5, 19.5, 4.5, 18, 4.5)
                p.line(6, 4.5); p.curve(4.5, 4.5, 3.5, 5.5, 3.5, 7); p.line(3.5, 17)
                p.curve(3.5, 18.5, 4.5, 19.5, 6, 19.5); p.line(10, 19.5)
            }
            c.stroke([(13, 20.5), (14, 17.5), (19, 12.5), (21.5, 15), (16.5, 20), (13, 20.5)])
        } else { c.roundedRect(3.5, 4.5, 17, 15, 2.8) }
        c.ellipse(13.5, 7.5, 3, 3)
        c.stroke([(4, 17), (8.5, 12), (13, 17)])
        if !editing { c.stroke([(13, 17), (16, 14), (20, 18)]) }
    }

    private static func smallArrow(_ c: CrabSymbolCanvas, upward: Bool) {
        if upward {
            c.stroke([(12, 18), (12, 10.5)]); c.stroke([(9, 13.5), (12, 10.5), (15, 13.5)])
        } else {
            c.stroke([(12, 10.5), (12, 18)]); c.stroke([(9, 15), (12, 18), (15, 15)])
        }
    }

    private static func scanCorners(_ c: CrabSymbolCanvas) {
        c.stroke([(3.5, 9), (3.5, 3.5), (9, 3.5)])
        c.stroke([(15, 3.5), (20.5, 3.5), (20.5, 9)])
        c.stroke([(20.5, 15), (20.5, 20.5), (15, 20.5)])
        c.stroke([(9, 20.5), (3.5, 20.5), (3.5, 15)])
    }

    private static func plus(_ c: CrabSymbolCanvas, x: CGFloat, y: CGFloat, arm: CGFloat) {
        c.stroke([(x - arm, y), (x + arm, y)]); c.stroke([(x, y - arm), (x, y + arm)])
    }

    private static func cross(_ c: CrabSymbolCanvas, x: CGFloat, y: CGFloat, arm: CGFloat) {
        c.stroke([(x - arm, y - arm), (x + arm, y + arm)])
        c.stroke([(x - arm, y + arm), (x + arm, y - arm)])
    }

    private static func sparkle(_ c: CrabSymbolCanvas, x: CGFloat, y: CGFloat, arm: CGFloat) {
        c.stroke([(x - arm, y), (x, y - arm), (x + arm, y), (x, y + arm)], closed: true)
    }

    private static func transformed(_ c: CrabSymbolCanvas, angle: CGFloat, _ body: () -> Void) {
        c.context.saveGState(); c.context.translateBy(x: 12, y: 12); c.context.rotate(by: angle)
        c.context.translateBy(x: -12, y: -12); body(); c.context.restoreGState()
    }

    private static func path(_ c: CrabSymbolCanvas, _ body: (Outline) -> Void) {
        let outline = Outline(); body(outline)
        c.context.addPath(outline.path); c.context.strokePath()
    }

    private final class Outline {
        let path = CGMutablePath()
        func move(_ x: CGFloat, _ y: CGFloat) { path.move(to: CGPoint(x: x, y: y)) }
        func line(_ x: CGFloat, _ y: CGFloat) { path.addLine(to: CGPoint(x: x, y: y)) }
        func curve(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
            path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
        }
        func close() { path.closeSubpath() }
    }
}
