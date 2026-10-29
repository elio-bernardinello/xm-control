import SwiftUI
import AppKit
import SonyHeadphonesKit

/// The cream identity of the approved mockups, and its warm dark counterpart.
/// Every token resolves from the effective appearance, so the same views serve both
/// modes without a single hard-coded colour in the layout code.
enum Mock {
    // MARK: - Appearance helpers

    private static func ns(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> Color {
        adaptive(ns(light, alpha), ns(dark, alpha))
    }

    // MARK: - Paper and ink

    static let paper = adaptive(0xF6F3EC, 0x171410)
    static let paperFlat = paper

    static let ink = adaptive(0x1C1A16, 0xF3EDE1)
    static let ink2 = adaptive(0x6B665C, 0xB8AF9F)
    static let ink3 = adaptive(0x9F9889, 0x8C8375)

    /// The accent used for text, links, focus and slider fills: midnight in the day,
    /// moonlight at night. It is deliberately not the fill colour of the night controls.
    static let accent = adaptive(0x2A3548, 0xAEC0E2)
    static let midnight = accent

    /// Fills for selected tiles, switches and the primary action.
    static let accentFill = adaptive(0x2A3548, 0x3A4A66)
    static let accentFillHi = adaptive(0x3C4A66, 0x4B5D7D)
    static let green = adaptive(0x3FA66A, 0x5FC98C)

    static let hair = adaptive(ns(0x3C321E, 0.09), ns(0xFFF4E0, 0.10))
    static let well = adaptive(ns(0x3C321E, 0.065), ns(0xFFF4E0, 0.06))
    static let card = adaptive(NSColor.white.withAlphaComponent(0.70), ns(0xFFF6E7, 0.055))
    static let cardBorder = adaptive(ns(0x3C321E, 0.08), ns(0xFFF5E1, 0.06))
    static let cardShadow = adaptive(ns(0x3C280A, 0.05), NSColor.black.withAlphaComponent(0.22))

    static let heroBorder = adaptive(ns(0x5A461E, 0.12), ns(0xFFF5E1, 0.08))
    static let heroShadow = adaptive(ns(0x3C280A, 0.08), NSColor.black.withAlphaComponent(0.28))
    static let artBorder = adaptive(ns(0x5A461E, 0.14), ns(0xFFF5E1, 0.10))
    static let artShadow = adaptive(ns(0x3C280A, 0.12), NSColor.black.withAlphaComponent(0.35))
    static let stageBorder = adaptive(ns(0x5A461E, 0.14), ns(0xFFF5E1, 0.10))
    static let stageShadow = adaptive(ns(0x3C280A, 0.14), NSColor.black.withAlphaComponent(0.45))

    static let switchOff = adaptive(ns(0x3C321E, 0.16), ns(0xFFF4E0, 0.13))
    static let switchKnob = adaptive(NSColor.white, ns(0xF2EBDD))
    static let sliderTrack = adaptive(ns(0x3C321E, 0.12), ns(0xFFF4E0, 0.10))
    static let sliderKnob = switchKnob
    static let segmentFill = adaptive(NSColor.white, ns(0x4E4638))
    static let segmentShadow = adaptive(ns(0x3C280A, 0.14), NSColor.black.withAlphaComponent(0.40))
    static let selectedText = adaptive(NSColor.white, ns(0xF7F2E8))
    static let primaryText = adaptive(NSColor.white, ns(0x1B1813))
    static let primaryShadow = adaptive(ns(0x2A3548, 0.30), NSColor.black.withAlphaComponent(0.38))
    static let markBorder = adaptive(ns(0x5A461E, 0.20), ns(0xFFF5E1, 0.12))
    static let markShadow = adaptive(ns(0x3C280A, 0.12), NSColor.black.withAlphaComponent(0.40))

    /// The one spacing unit of every surface: cards, stacks and the popover padding.
    static let gap: CGFloat = 16

    // MARK: - Surfaces

    /// The popover of the mockup is a hair lighter than the page.
    static var popoverPaper: LinearGradient {
        LinearGradient(
            colors: [adaptive(ns(0xFBF9F4), ns(0x201C16, 0.97)),
                     adaptive(ns(0xF5F1E9), ns(0x171410, 0.98))],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// The disconnected stage keeps the soft light of the maquette, and its warm halo at night.
    static var emptyPaper: RadialGradient {
        RadialGradient(
            colors: [adaptive(0xFBF9F4, 0x241F18),
                     adaptive(0xF1ECE1, 0x1B1712),
                     adaptive(0xE8E1D2, 0x15120E)],
            center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 620
        )
    }

    static var heroFill: LinearGradient {
        LinearGradient(
            colors: [adaptive(NSColor.white.withAlphaComponent(0.92), ns(0x2C261E)),
                     adaptive(0xF4EEE2, 0x211C16),
                     adaptive(0xE9DFCB, 0x1B1712)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static var heroArtFill: RadialGradient {
        RadialGradient(
            colors: [adaptive(NSColor.white, ns(0x3C342A)),
                     adaptive(0xEADFC9, 0x241F19)],
            center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 120
        )
    }

    static var stageFill: RadialGradient {
        RadialGradient(
            colors: [adaptive(NSColor.white, ns(0x3E362B)),
                     adaptive(0xEFE6D4, 0x241F19)],
            center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0, endRadius: 170
        )
    }

    static var selectedTileFill: LinearGradient {
        LinearGradient(colors: [accentFillHi, accentFill], startPoint: .top, endPoint: .bottom)
    }

    static var primaryFill: LinearGradient {
        LinearGradient(
            colors: [adaptive(0x3C4A66, 0xF4EDDF), adaptive(0x2A3548, 0xE7DDCA)],
            startPoint: .top, endPoint: .bottom
        )
    }

    static var markFill: LinearGradient {
        LinearGradient(
            colors: [adaptive(0xFCF9F2, 0x3B342A), adaptive(0xE8DCC6, 0x221D17)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

/// The app's five text sizes, the only ones any view uses: 26, 22, 15, 13, 11.
/// macOS does not scale text for Dynamic Type, so the scale is fixed and matches the mockups.
enum MockType {
    static let largeTitle = Font.system(size: 26, weight: .bold)
    static let heading = Font.system(size: 15, weight: .semibold)
    static let headingRegular = Font.system(size: 15)
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionStrong = Font.system(size: 11, weight: .semibold)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Keyboard focus, drawn the same way for every custom control.
private struct FocusRing: ViewModifier {
    let visible: Bool
    var cornerRadius: CGFloat = 9

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Mock.accent, lineWidth: 2)
                .opacity(visible ? 1 : 0)
        )
    }
}

/// A translucent cream card with the hairline and soft lift of the mockups. In a row,
/// cards stretch to the row's height, so neighbours always end on the same line.
struct MockCard<Content: View>: View {
    let title: String
    let icon: String
    var hint: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(MockType.body)
                    .foregroundStyle(Mock.ink2)
                Text(title)
                    .font(MockType.bodyStrong)
                    .foregroundStyle(Mock.ink)
                Spacer(minLength: 8)
                if let hint {
                    Text(hint)
                        .font(MockType.caption)
                        .foregroundStyle(Mock.ink3)
                        .lineLimit(1)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Mock.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Mock.cardBorder, lineWidth: 0.5)
        )
        .shadow(color: Mock.cardShadow, radius: 9, y: 6)
    }
}

/// A settings row inside a card: label leading, control trailing, hairline above.
struct MockRow<Trailing: View>: View {
    let label: String
    var first = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(Mock.hair).frame(height: 0.5) }
            HStack(spacing: 10) {
                Text(label)
                    .font(MockType.body)
                    .foregroundStyle(Mock.ink)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.vertical, 9)
        }
    }
}

/// A switch row. The control is a native `Toggle`, so VoiceOver, the switch role and the
/// keyboard come from the system; only its appearance follows the mockup.
struct MockToggleRow: View {
    let label: String
    let isOn: Bool
    var first = false
    let onChange: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(Mock.hair).frame(height: 0.5) }
            Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
                Text(label)
            }
            .toggleStyle(MockSwitchStyle())
            .padding(.vertical, 9)
        }
    }
}

/// The mockup's pill switch: midnight when on, a quiet well when off.
struct MockSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
                .font(MockType.body)
                .foregroundStyle(Mock.ink)
            Spacer(minLength: 8)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? AnyShapeStyle(Mock.accentFill) : AnyShapeStyle(Mock.switchOff))
                    .frame(width: 36, height: 22)
                Circle()
                    .fill(Mock.switchKnob)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .padding(2)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
    }
}

/// A value chip that opens a menu, as in the mockup's preset control.
struct MockValueMenu<Option: Hashable>: View {
    let selection: Option?
    let options: [Option]
    let label: (Option) -> String
    let select: (Option) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(label(option)) { select(option) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection.map(label) ?? "—")
                    .font(MockType.bodyStrong)
                    .foregroundStyle(Mock.ink)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Mock.ink3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Mock.well))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The tall tile selector of the listening modes: icon over a one-word label, the
/// chosen tile filled in midnight. Tiles share the width equally.
struct TileSegment<Option: Hashable>: View {
    struct Item: Identifiable {
        let value: Option
        let title: String
        let symbol: String
        var id: Option { value }
    }
    let items: [Item]
    let selection: Option?
    let select: (Option) -> Void
    @FocusState private var focused: Option?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items) { item in
                let selected = item.value == selection
                Button { select(item.value) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 20, weight: .light))
                            .frame(height: 22)
                        Text(item.title)
                            .font(MockType.captionStrong)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? Mock.selectedText : Mock.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Mock.selectedTileFill) : AnyShapeStyle(Color.clear))
                            .shadow(color: selected ? Mock.accentFill.opacity(0.28) : .clear, radius: 3, y: 2)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($focused, equals: item.value)
                .modifier(FocusRing(visible: focused == item.value))
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Mock.well))
        .animation(.easeOut(duration: 0.18), value: selection)
    }
}

/// The compact segmented control: a white pill on a warm well, equal segment widths.
struct CompactSegment<Option: Hashable>: View {
    let items: [(value: Option, title: String)]
    let selection: Option?
    let select: (Option) -> Void
    @FocusState private var focused: Option?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let selected = item.value == selection
                Button { select(item.value) } label: {
                    Text(item.title)
                        .font(selected ? MockType.bodyStrong : Font.system(size: 13))
                        .foregroundStyle(selected ? Mock.ink : Mock.ink2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(selected ? Mock.segmentFill : Color.clear)
                                .shadow(color: selected ? Mock.segmentShadow : .clear, radius: 1.5, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($focused, equals: item.value)
                .modifier(FocusRing(visible: focused == item.value))
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Mock.well))
        .animation(.easeOut(duration: 0.18), value: selection)
    }
}

/// The slim slider of the mockup. It takes the keyboard (left and right arrows) and
/// VoiceOver's adjust gesture, and it draws its own focus ring.
struct MockSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void
    @FocusState private var focused: Bool

    private func clamped(_ candidate: Double) -> Double {
        min(max(candidate, range.lowerBound), range.upperBound)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(Mock.sliderTrack).frame(height: 4)
                Capsule().fill(Mock.accent).frame(width: max(4, width * fraction), height: 4)
                Circle()
                    .fill(Mock.sliderKnob)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                    .offset(x: width * fraction - 8)
            }
            .frame(width: width, height: 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let f = min(max(drag.location.x / width, 0), 1)
                onChange(clamped(range.lowerBound + f * (range.upperBound - range.lowerBound)))
            })
        }
        .frame(height: 16)
        .focusable()
        .focused($focused)
        .modifier(FocusRing(visible: focused, cornerRadius: 6))
        .onMoveCommand { direction in
            switch direction {
            case .left: onChange(clamped(value - 1))
            case .right: onChange(clamped(value + 1))
            default: break
            }
        }
        .accessibilityElement()
        .accessibilityValue("\(Int(value.rounded()))")
        .accessibilityAdjustableAction { direction in
            onChange(clamped(direction == .increment ? value + 1 : value - 1))
        }
    }
}

/// One equalizer band: a thin track and a knob at its gain, dragged vertically. Arrow
/// keys and VoiceOver adjust it one step at a time; it is inert unless the custom curve is active.
struct EqBand: View {
    let value: Int
    let range: ClosedRange<Int>
    let enabled: Bool
    let onChange: (Int) -> Void
    @FocusState private var focused: Bool

    private func clamped(_ candidate: Int) -> Int {
        min(max(candidate, range.lowerBound), range.upperBound)
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let fraction = Double(value - range.lowerBound) / Double(range.upperBound - range.lowerBound)
            ZStack {
                Capsule().fill(Mock.sliderTrack).frame(width: 3)
                Circle()
                    .fill(Mock.sliderKnob)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                    .offset(y: (0.5 - fraction) * (height - 14))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard enabled else { return }
                let f = 1 - min(max(drag.location.y / height, 0), 1)
                let gain = Double(range.lowerBound) + f * Double(range.upperBound - range.lowerBound)
                let rounded = clamped(Int(gain.rounded()))
                if rounded != value { onChange(rounded) }
            })
        }
        .opacity(enabled ? 1 : 0.6)
        .focusable(enabled)
        .focused($focused)
        .modifier(FocusRing(visible: focused && enabled, cornerRadius: 6))
        .onMoveCommand { direction in
            guard enabled else { return }
            switch direction {
            case .up: onChange(clamped(value + 1))
            case .down: onChange(clamped(value - 1))
            default: break
            }
        }
        .accessibilityElement()
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            onChange(clamped(direction == .increment ? value + 1 : value - 1))
        }
    }
}

/// The app mark of the mockups: the headphone glyph on a cream tile.
struct MockMark: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(Mock.markFill)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .strokeBorder(Mock.markBorder, lineWidth: 0.5)
                )
                .shadow(color: Mock.markShadow, radius: 1, y: 1)
            HeadphoneImage().padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension ListeningMode {
    /// The one-word tile captions of the mockups.
    var tileLabel: String {
        switch self {
        case .standard: return "Standard"
        case .backgroundMusic: return "Fond"
        case .cinema: return "Cinéma"
        }
    }
}

/// Glyph for an audio source, guessed from its advertised name.
func symbolForDevice(named name: String) -> String {
    let lowered = name.lowercased()
    if lowered.contains("iphone") || lowered.contains("phone") { return "iphone" }
    if lowered.contains("ipad") || lowered.contains("tab") { return "ipad" }
    if lowered.contains("watch") { return "applewatch" }
    if lowered.contains("book") || lowered.contains("mac") || lowered.contains("pc") { return "laptopcomputer" }
    return "desktopcomputer"
}
