import SwiftUI
import AppKit
import SonyHeadphonesKit

/// One colour scale for battery charge, shared by the panel gauge and the menu bar
/// badge so the two can never disagree about what "low" looks like.
///
/// Bands, from full to empty: green from 100 % down to 50 %, orange down to 20 %,
/// red below. The hues are tuned rather than the system defaults: vivid enough to
/// read on a light menu bar and a dark one, and warm enough to sit with the app's
/// champagne accent instead of looking like a traffic light.
enum BatteryTint {
    static let green = NSColor(red: 0.18, green: 0.72, blue: 0.42, alpha: 1)
    static let orange = NSColor(red: 0.96, green: 0.62, blue: 0.11, alpha: 1)
    /// Softer than a stop sign, and the tone the current macOS battery indicator
    /// uses at critical charge: red enough to alarm, warm enough to sit with the
    /// app's champagne palette.
    static let red = NSColor(red: 0.86, green: 0.44, blue: 0.37, alpha: 1)

    static func nsColor(level: Int, charging: Bool) -> NSColor {
        if charging { return green }
        switch level {
        case ..<21: return red
        case ..<50: return orange
        default: return green
        }
    }

    static func color(level: Int, charging: Bool) -> Color {
        Color(nsColor: nsColor(level: level, charging: charging))
    }
}

/// A drawn battery gauge rather than an SF Symbol plus a number: the fill level is
/// readable at a glance, and it gives the header a piece of real instrumentation
/// instead of another line of text.
///
/// The shape follows the battery indicator of the current macOS: one soft rounded
/// body with a fine rim, a neutral track, and a charge bar inset on all sides so it
/// never touches the rim. That inset is what makes a low level read as a small
/// capsule in the gauge rather than as a half-filled rectangle, and it keeps the
/// silhouette calm next to the app's other controls. The terminal nub and the
/// percentage sit outside the body, the way the system draws them.
struct BatteryGauge: View {
    let level: Int
    let isCharging: Bool

    private static let bodyWidth: CGFloat = 30
    private static let bodyHeight: CGFloat = 14
    /// Gap between the rim and the charge bar, all the way round.
    private static let inset: CGFloat = 2
    private static let corner: CGFloat = 4
    private static let fillCorner: CGFloat = 2

    private var tint: Color {
        BatteryTint.color(level: level, charging: isCharging)
    }

    private var fillWidth: CGFloat {
        let usable = Self.bodyWidth - Self.inset * 2
        let clamped = CGFloat(min(max(level, 0), 100)) / 100
        // Never fully empty, so the gauge still reads as a gauge at 0 %.
        return max(3, usable * clamped)
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 1.5) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                        .fill(BatteryPalette.track)

                    RoundedRectangle(cornerRadius: Self.fillCorner, style: .continuous)
                        .fill(tint)
                        .frame(width: fillWidth, height: Self.bodyHeight - Self.inset * 2)
                        .padding(.leading, Self.inset)

                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1)
                            .frame(width: Self.bodyWidth, alignment: .center)
                    }
                }
                .frame(width: Self.bodyWidth, height: Self.bodyHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                        .strokeBorder(BatteryPalette.rim, lineWidth: 1)
                )

                // Terminal cap.
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(BatteryPalette.nub)
                    .frame(width: 2, height: 5)
            }

            Text("\(level)%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Batterie à \(level) pour cent\(isCharging ? ", en charge" : "")")
    }
}

/// Neutral greys behind the charge bar, resolved per appearance rather than from
/// `.primary` opacity: a translucent track picks up the cream panel and turns warm,
/// while the system's battery is a flat cool grey in both light and dark mode.
private enum BatteryPalette {
    static let track = adaptive(light: NSColor(white: 0.741, alpha: 1),
                               dark: NSColor(white: 0.302, alpha: 1))
    static let rim = adaptive(light: NSColor(white: 0.639, alpha: 1),
                              dark: NSColor(white: 0.443, alpha: 1))
    static let nub = adaptive(light: NSColor(white: 0.729, alpha: 1),
                              dark: NSColor(white: 0.510, alpha: 1))

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
