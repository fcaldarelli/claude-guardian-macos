import AppKit

/// Disegna l'etichetta della barra dei menu ("⚙ 3  ✋ 1") come un'unica immagine.
///
/// MenuBarExtra non mostra in modo affidabile le SF Symbol inserite in un Text,
/// mentre un'immagine "template" viene sempre visualizzata e macOS la colora
/// da solo in base alla barra chiara o scura.
enum MenuBarIcon {

    private static let height: CGFloat = 18
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

    static func image(working: Int, waiting: Int, idle: Int, hasSessions: Bool) -> NSImage {
        guard hasSessions else {
            return symbolOnly("sparkle")
        }
        return compose([
            ("gearshape.2.fill", "\(working)"),
            ("hand.raised.fill", "\(waiting)"),
            ("moon.zzz.fill", "\(idle)"),
        ])
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
    }

    private static func symbolOnly(_ name: String) -> NSImage {
        let image = symbol(name) ?? NSImage(size: NSSize(width: height, height: height))
        image.isTemplate = true
        return image
    }

    private static func compose(_ items: [(symbol: String, text: String)]) -> NSImage {
        let iconTextGap: CGFloat = 3
        let itemGap: CGFloat = 7
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black, // per un'immagine template conta solo l'opacità
        ]

        let parts: [(image: NSImage?, text: NSAttributedString)] = items.map {
            (symbol($0.symbol), NSAttributedString(string: $0.text, attributes: attributes))
        }

        var width: CGFloat = 0
        for (index, part) in parts.enumerated() {
            width += (part.image?.size.width ?? 0) + iconTextGap + ceil(part.text.size().width)
            if index < parts.count - 1 { width += itemGap }
        }

        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for part in parts {
                if let icon = part.image {
                    let y = (height - icon.size.height) / 2
                    icon.draw(in: NSRect(x: x, y: y, width: icon.size.width, height: icon.size.height))
                    x += icon.size.width + iconTextGap
                }
                let textSize = part.text.size()
                part.text.draw(at: NSPoint(x: x, y: (height - textSize.height) / 2))
                x += ceil(textSize.width) + itemGap
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = items.map { "\($0.symbol) \($0.text)" }.joined(separator: ", ")
        return image
    }
}
