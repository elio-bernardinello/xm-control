import SwiftUI

/// Short, consistent feedback for hardware controls. Deliberately no spring
/// overshoot: the interface should settle as soon as the headphones confirm a state.
enum Motion {
    static let press = Animation.easeOut(duration: 0.11)
    static let hover = Animation.easeOut(duration: 0.12)
    static let selection = Animation.easeInOut(duration: 0.21)
    static let section = Animation.easeInOut(duration: 0.23)
    static let sceneChange = Animation.easeInOut(duration: 0.26)

    /// Compatibility for existing expandable sections.
    static let transition = section
    static let selectionDuration: TimeInterval = 0.21
}

/// Tracks pointer hover for a single view.
///
/// An `ObservableObject` rather than `@State` because this project builds against the
/// Command Line Tools, which ship no SwiftUI macro plugin, so `@State` cannot compile
/// here at all. `@StateObject` works, and gives the same per-view lifetime.
final class HoverState: ObservableObject {
    @Published var isHovering = false
}

/// Restrained press feedback for any button.
///
/// Uses `ButtonStyle`'s own `isPressed`, so it needs no view-local state and works on
/// every control uniformly, including the ones built out of plain shapes.
struct PressableButtonStyle: ButtonStyle {
    /// How far the control sinks. Circles can take more than wide chips before the
    /// movement starts to look like a glitch.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
            .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
    }
}

/// Lifts a surface slightly under the pointer: a touch more elevation and a hair of
/// scale, so cards feel like objects rather than printed panels.
struct HoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var hover = HoverState()

    var scale: CGFloat = 1.006
    var shadowOpacity: Double = 0.22

    func body(content: Content) -> some View {
        content
            .scaleEffect(hover.isHovering && !reduceMotion ? scale : 1.0)
            .shadow(
                color: Color.black.opacity(hover.isHovering ? shadowOpacity : 0),
                radius: 18,
                y: 8
            )
            .animation(reduceMotion ? nil : Motion.hover, value: hover.isHovering)
            .onHover { hover.isHovering = $0 }
    }
}

extension View {
    func hoverLift(scale: CGFloat = 1.006, shadowOpacity: Double = 0.22) -> some View {
        modifier(HoverLift(scale: scale, shadowOpacity: shadowOpacity))
    }
}
