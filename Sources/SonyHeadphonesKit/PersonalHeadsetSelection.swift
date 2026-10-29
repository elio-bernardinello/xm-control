import Foundation

/// Resolves one personal headset without exposing unrelated paired Bluetooth devices.
///
/// Supported names (case-insensitive):
/// - factory names: WH-1000XM4 / WH-1000XM5 / WH-1000XM6
/// - custom names containing a generation: "Mon XM6", "Casque de Marie XM5", "XM4"
/// - an explicit custom display name set in Preferences (exact match)
/// A remembered Bluetooth address always wins, even after a rename.
enum PersonalHeadsetSelection {
    static func preferred(
        in devices: [PairedDeviceInfo],
        rememberedAddress: String?,
        customName: String? = nil,
        preferredModel: HeadsetModel? = nil
    ) -> PairedDeviceInfo? {
        if let address = rememberedAddress {
            return devices.first { $0.id.caseInsensitiveCompare(address) == .orderedSame }
        }
        if let customName {
            let wanted = normalized(customName)
            if !wanted.isEmpty {
                let exact = devices.filter { normalized($0.name) == wanted }
                if exact.count == 1 { return exact[0] }
            }
        }
        var candidates = devices.filter { isXMDevice(named: $0.name) }
        if let preferredModel {
            let narrowed = candidates.filter { HeadsetModel.detect(fromName: $0.name) == preferredModel }
            // A model preference disambiguates only when it isolates one device.
            if narrowed.count == 1 { return narrowed[0] }
            // If the preference matches none, fall through to the full list rather
            // than hiding a valid headset.
            if !narrowed.isEmpty { candidates = narrowed }
        }
        if candidates.count == 1 { return candidates[0] }
        return nil
    }

    /// True for factory names and for user-renamed headsets that still mention
    /// their generation ("Mon XM6", "Marie XM5", "XM4").
    static func isXMDevice(named name: String) -> Bool {
        HeadsetModel.detect(fromName: name) != nil
    }

    static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
