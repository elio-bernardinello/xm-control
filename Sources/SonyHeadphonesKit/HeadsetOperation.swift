import Foundation

public enum CommandOperation: Equatable, Sendable {
    case idle
    case pending
    case failed(String)
}

public enum HeadsetFeature: CaseIterable, Hashable, Sendable {
    case battery, ambientSound, speakToChat, speakToChatConfig, automaticPowerOff
    case wearDetection, equalizer, listeningMode, devices
}

public enum FeatureAvailability: Equatable, Sendable {
    case loading, available, notReported
}

/// Injectable deadlines keep lifecycle tests independent of hardware and long waits.
struct HeadsetSessionTiming {
    var connect: UInt64 = 8_000_000_000
    var handshake: UInt64 = 1_250_000_000
    var acknowledgement: UInt64 = 3_000_000_000
    var initialState: UInt64 = 6_000_000_000
    var operation: UInt64 = 12_000_000_000
    var equalizerDebounce: UInt64 = 90_000_000
    /// Re-read after a physical-button notification, and periodic safety re-read.
    var ambientVerify: UInt64 = 350_000_000
    var ambientPoll: UInt64 = 4_000_000_000
    /// Liveness probe while connected: a cheap read at this interval, so a dead link
    /// is noticed in seconds rather than when the next command happens to fail.
    var heartbeat: UInt64 = 3_000_000_000
    /// Periodic re-read of the multipoint source list while connected, so a steal
    /// by the other device shows up without a manual refresh.
    var devicePoll: UInt64 = 8_000_000_000
    /// Longest silence tolerated from the headset before the link counts as lost.
    var silence: UInt64 = 10_000_000_000
    /// Pauses before each automatic reconnection attempt. Its length is the number of
    /// attempts; after the last one the session gives up and shows the failure.
    var reconnectDelays: [UInt64] = [2_000_000_000, 4_000_000_000, 8_000_000_000,
                                     15_000_000_000, 15_000_000_000, 15_000_000_000]
}
