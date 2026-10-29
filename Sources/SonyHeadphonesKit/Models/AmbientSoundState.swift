import Foundation

public enum AmbientSoundMode: String, CaseIterable, Sendable {
    case off
    case noiseCancelling
    case ambientSound
}

public struct AmbientSoundState: Equatable, Sendable {
    public var mode: AmbientSoundMode
    public var focusOnVoice: Bool
    /// 0...20, only meaningful while `mode == .ambientSound`.
    public var level: Int

    /// The subtype byte the device itself reported (0x19 on the XM6, 0x15, 0x17 or
    /// 0x22 elsewhere). Writes echo it back so we always speak whichever dialect
    /// the firmware speaks, instead of assuming one.
    public var subtype: UInt8
    /// Bytes between the ambient flag and the focus/level tail, exactly as the
    /// device reported them: the wind-noise byte on the 0x17 form, two fixed bytes
    /// on the XM6's 0x19 form. Echoed verbatim on writes — this firmware stores
    /// the body it receives, so inventing bytes here would overwrite settings we
    /// cannot read.
    public var midBytes: [UInt8]
    /// Whether the device's reply included the extra wind-noise-mode byte
    /// (only seen with subtype 0x17 and an 8-byte payload).
    public var hasWindNoiseByte: Bool
    /// Set by the decoder: the report came from an unsolicited notification (for
    /// example the physical button on the headphones) rather than from a read.
    public var isNotification: Bool

    public init(
        mode: AmbientSoundMode = .noiseCancelling,
        focusOnVoice: Bool = false,
        level: Int = 15,
        subtype: UInt8 = 0x15,
        midBytes: [UInt8] = [],
        hasWindNoiseByte: Bool = false,
        isNotification: Bool = false
    ) {
        self.mode = mode
        self.focusOnVoice = focusOnVoice
        self.level = max(0, min(20, level))
        self.subtype = subtype
        self.midBytes = midBytes
        self.hasWindNoiseByte = hasWindNoiseByte
        self.isNotification = isNotification
    }
}
