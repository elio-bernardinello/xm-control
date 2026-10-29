import Foundation

/// Persists the user's own headset choice. No personal data is shipped in the
/// app: every value here is entered by the user on their own Mac.
struct PersonalHeadsetPreferences {
    let defaults: UserDefaults
    var address: String? { defaults.string(forKey: "personalHeadsetAddress") }
    var name: String? { defaults.string(forKey: "personalHeadsetName") }

    /// Free-form display name typed by the user, e.g. "Casque de Marie",
    /// "Mon XM6". Shown in the UI instead of the raw Bluetooth name when set.
    var customDisplayName: String? {
        let raw = defaults.string(forKey: "customDisplayName")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    /// Optional owner first name, used only to suggest a default display name.
    /// Never sent anywhere.
    var ownerName: String? {
        let raw = defaults.string(forKey: "ownerName")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    /// Preferred generation ("Automatique", "XM4", "XM5", "XM6").
    var modelPreference: HeadsetModelPreference {
        HeadsetModelPreference.fromStored(defaults.string(forKey: "preferredHeadsetModel"))
    }

    func remember(address: String, name: String?) {
        defaults.set(address, forKey: "personalHeadsetAddress")
        if let name { defaults.set(name, forKey: "personalHeadsetName") }
    }

    func setCustomDisplayName(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            defaults.removeObject(forKey: "customDisplayName")
        } else {
            defaults.set(trimmed, forKey: "customDisplayName")
        }
    }

    func setOwnerName(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            defaults.removeObject(forKey: "ownerName")
        } else {
            defaults.set(trimmed, forKey: "ownerName")
        }
    }

    func setModelPreference(_ preference: HeadsetModelPreference) {
        if preference == .auto {
            defaults.removeObject(forKey: "preferredHeadsetModel")
        } else {
            defaults.set(preference.rawValue, forKey: "preferredHeadsetModel")
        }
    }

    func clearRememberedHeadset() {
        defaults.removeObject(forKey: "personalHeadsetAddress")
        defaults.removeObject(forKey: "personalHeadsetName")
    }
}
