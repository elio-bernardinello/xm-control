import Foundation

/// Supported Sony 1000X generations. The control protocol is shared across the
/// series (Sony "v2" transport for XM5/XM6, compatible subset for XM4); features
/// the connected headset does not report are shown as unavailable instead of
/// being assumed.
public enum HeadsetModel: String, CaseIterable, Identifiable, Equatable {
    case xm4 = "XM4"
    case xm5 = "XM5"
    case xm6 = "XM6"

    public var id: String { rawValue }
    /// Factory Bluetooth name fragment, e.g. WH-1000XM6.
    public var factoryName: String { "WH-1000\(rawValue)" }
    /// Short label used in the UI.
    public var shortLabel: String { rawValue }
    /// Full label used in headers and accessibility.
    public var fullLabel: String { factoryName }

    /// Detects the model from a Bluetooth name such as "WH-1000XM5",
    /// "Mon XM4" or "Marie’s XM6". Returns nil when no generation is mentioned.
    public static func detect(fromName name: String) -> HeadsetModel? {
        let lowered = name.lowercased()
        if lowered.contains("1000xm6") || lowered.contains("xm6") { return .xm6 }
        if lowered.contains("1000xm5") || lowered.contains("xm5") { return .xm5 }
        if lowered.contains("1000xm4") || lowered.contains("xm4") { return .xm4 }
        return nil
    }
}

/// User preference for which generation to prefer when several XM headsets are
/// paired. "auto" (nil) means: pick the single XM candidate, otherwise ask.
public enum HeadsetModelPreference: String, CaseIterable, Identifiable {
    case auto = "Automatique"
    case xm4 = "XM4"
    case xm5 = "XM5"
    case xm6 = "XM6"

    public var id: String { rawValue }
    public var model: HeadsetModel? {
        switch self {
        case .auto: return nil
        case .xm4: return .xm4
        case .xm5: return .xm5
        case .xm6: return .xm6
        }
    }

    public var displayLabel: String {
        switch self {
        case .auto: return L("Automatique", "Automatic")
        case .xm4, .xm5, .xm6: return rawValue
        }
    }

    public static func fromStored(_ raw: String?) -> HeadsetModelPreference {
        guard let raw else { return .auto }
        return HeadsetModelPreference(rawValue: raw) ?? .auto
    }
}
