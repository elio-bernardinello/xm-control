import AppKit

/// The menu bar item: the headphones sit inside their own battery ring, which fills
/// clockwise from twelve o'clock with the charge. One square glyph, no text, so the
/// menu bar stays uncluttered; the exact figure lives in the panel one click away.
///
/// The ring carries the colour — green, orange or red, the same scale as the
/// panel's gauge — while the headphones stay in the menu bar's own ink, so the
/// glyph reads like every other status item. Only a critical charge (below 20 %,
/// not charging) tints the glyph too: there the whole item has to shout.
///
/// Disconnected, still-connecting, or connected without a battery report: the ring
/// stays empty and the glyph dims, rather than inventing a level.
enum MenuBarBadge {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected(level: Int?, charging: Bool)
    }

    /// The tallest a status item image can be without the menu bar scaling it down.
    static let side: CGFloat = 22

    static func image(for state: State, darkMenuBar: Bool) -> NSImage {
        var level: Int?
        var charging = false
        var glyphAlpha: CGFloat = 1
        var trackAlpha: CGFloat = 0.28
        switch state {
        case .disconnected: glyphAlpha = 0.45; trackAlpha = 0.16
        case .connecting: glyphAlpha = 0.7; trackAlpha = 0.22
        case .connected(let value, let isCharging): level = value; charging = isCharging
        }

        // The menu bar's own ink, passed in rather than resolved here: an offscreen
        // image has no menu bar appearance to ask.
        let label: NSColor = darkMenuBar ? .white : .black
        // Colour only once the headset has reported a level: an unknown state must
        // not wear the colour of a healthy battery.
        let tint: NSColor? = level.map { BatteryTint.nsColor(level: $0, charging: charging) }
        let ringInk = tint ?? label
        let critical = (level ?? 100) < 20 && !charging
        let glyphInk = critical ? BatteryTint.nsColor(level: level ?? 0, charging: false) : label
        // Resolved once per state change, not again on every redraw of the status item.
        let headphones = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12.5, weight: .medium))
            .map { tinted($0, with: glyphInk) }

        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: side / 2, y: side / 2)
            let lineWidth: CGFloat = 2.2
            let radius = side / 2 - lineWidth / 2 - 0.4

            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.setStrokeColor(ringInk.withAlphaComponent(trackAlpha).cgColor)
            context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            context.strokePath()

            // Charge: from twelve o'clock, clockwise.
            if let level {
                let fraction = CGFloat(min(max(level, 0), 100)) / 100
                if fraction > 0 {
                    context.setStrokeColor(ringInk.cgColor)
                    context.addArc(center: center, radius: radius, startAngle: .pi / 2,
                                   endAngle: .pi / 2 - fraction * 2 * .pi, clockwise: true)
                    context.strokePath()
                }
            }

            // Charging: a bolt on the ring's lower left, cut out of the arc so it
            // stays legible wherever the charge level ends. Drawn before the
            // headphones, so its halo clears the ring and never the glyph.
            if charging {
                let bolt = boltPath(in: CGRect(x: 0.6, y: 0.5, width: 5.8, height: 7.6))
                context.saveGState()
                context.setBlendMode(.clear)
                context.setLineWidth(2.6)
                context.setLineJoin(.round)
                context.addPath(bolt)
                context.strokePath()
                context.addPath(bolt)
                context.fillPath()
                context.restoreGState()
                context.setFillColor(ringInk.cgColor)
                context.addPath(bolt)
                context.fillPath()
            }

            // Headphones, centred in the ring: menu bar ink, red only when the
            // battery is about to die.
            if let symbol = headphones {
                let size = symbol.size
                context.saveGState()
                context.setAlpha(glyphAlpha)
                symbol.draw(in: NSRect(x: center.x - size.width / 2,
                                       y: center.y - size.height / 2 + 0.2,
                                       width: size.width, height: size.height))
                context.restoreGState()
            }

            return true
        }
        // Never a template: the ring is a real colour, so macOS must not recolour
        // the whole image with the menu bar tint.
        image.isTemplate = false
        return image
    }

    /// SF Symbols draw in black; `sourceAtop` recolours exactly what they painted
    /// and leaves the rest of the badge alone.
    private static func tinted(_ symbol: NSImage, with color: NSColor) -> NSImage {
        NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func boltPath(in r: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX + r.width * 0.62, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.44))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.48, y: r.minY + r.height * 0.44))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.88, y: r.minY + r.height * 0.56))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.52, y: r.minY + r.height * 0.56))
        p.closeSubpath()
        return p
    }
}
