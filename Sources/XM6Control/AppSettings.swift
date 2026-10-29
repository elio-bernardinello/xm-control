import SwiftUI
import AppKit

/// App-level preferences, as opposed to headphone settings.
///
/// The menu-bar-only mode is applied at runtime rather than through `LSUIElement`
/// in the bundle: an `LSUIElement` app can never show a Dock icon or open a window
/// on launch, so the choice has to be a switchable activation policy instead of a
/// build-time fact.
@MainActor
final class AppSettings: ObservableObject {
    static let menuBarOnlyKey = "menuBarOnly"

    /// Readable before the first `AppSettings` instance exists, so the app can pick
    /// its activation policy during launch instead of showing a Dock icon first.
    static var storedMenuBarOnly: Bool {
        UserDefaults.standard.bool(forKey: menuBarOnlyKey)
    }

    /// `true` runs as a menu bar accessory: no Dock icon, no app-switcher entry, the
    /// menu bar panel is the whole interface. `false` is a normal Mac app.
    @Published var menuBarOnly: Bool {
        didSet {
            guard oldValue != menuBarOnly else { return }
            UserDefaults.standard.set(menuBarOnly, forKey: Self.menuBarOnlyKey)
            apply(openWindowIfNeeded: true)
        }
    }

    /// Opens the standard macOS Settings window from the menu bar panel as well.
    static func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.sendAction(NSSelectorFromString("showSettingsWindow:"), to: nil, from: nil) {
            NSApp.sendAction(NSSelectorFromString("showPreferencesWindow:"), to: nil, from: nil)
        }
    }

    init() {
        menuBarOnly = UserDefaults.standard.bool(forKey: Self.menuBarOnlyKey)
    }

    /// Pushes the current preference onto `NSApp`. Call once at launch, and it runs
    /// again automatically whenever the preference changes.
    ///
    /// - Parameter openWindowIfNeeded: when leaving menu-bar-only mode, bring the app
    ///   forward so the change is visible; there is otherwise no feedback that the
    ///   Dock icon came back.
    func apply(openWindowIfNeeded: Bool = false) {
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)

        if !menuBarOnly && openWindowIfNeeded {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
