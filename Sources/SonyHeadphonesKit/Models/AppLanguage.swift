import Foundation

/// Interface language. The app ships French + English; the user picks in
/// Settings, otherwise the system language decides (French if it starts with
/// "fr", English otherwise). Stored under "appLanguage" as
/// "system" / "fr" / "en".
public enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case fr
    case english = "en"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return AppEnglish ? "System" : "Système"
        case .fr: return "Français"
        case .english: return "English"
        }
    }
}

/// True when the UI should read English. Reads UserDefaults directly (no
/// observable wrapper) so both the app and headless tools/tests agree;
/// every view showing these strings also observes the controller, which
/// re-announces on language change (see `noteLanguageChanged`).
public var AppEnglish: Bool {
    let stored = UserDefaults.standard.string(forKey: "appLanguage")
    if stored == "fr" { return false }
    if stored == "en" { return true }
    return !(Locale.preferredLanguages.first?.hasPrefix("fr") ?? false)
}

/// Localize one user-facing string. French first (historic default), English
/// second. Non-user-facing code comments stay as they are.
public func L(_ fr: String, _ en: String) -> String { AppEnglish ? en : fr }
