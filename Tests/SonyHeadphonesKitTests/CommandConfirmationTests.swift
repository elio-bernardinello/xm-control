import XCTest
@testable import SonyHeadphonesKit

private final class ConfirmationTransport: HeadphonesTransport {
    var onEvent: ((RFCOMMConnectionEvent) -> Void)?
    var writes: [SonyMessage] = []
    func connect(toDeviceAddress address: String) {}
    func disconnect() {}
    func write(_ bytes: [UInt8]) { if let value = SonyMessage.decode(rawFrame: bytes) { writes.append(value) } }
    var commands: [SonyMessage] { writes.filter { $0.type != .ack } }
    func receive(_ payload: [UInt8]) {
        onEvent?(.dataReceived(SonyMessage(type: .command1, sequenceNumber: 0, payload: payload).encode()))
    }
    func ack(_ command: SonyMessage) {
        onEvent?(.dataReceived(SonyMessage(type: .ack, sequenceNumber: command.sequenceNumber ^ 1, payload: []).encode()))
    }
}

@MainActor
private final class ConfirmationFixture {
    let transport = ConfirmationTransport()
    let controller: HeadphonesController
    let defaults: UserDefaults
    let suite = "XMControl.ConfirmationTests.\(UUID().uuidString)"
    private var acknowledged = 0
    init(operationTimeout: UInt64 = 10_000_000_000, ambientVerify: UInt64 = 350_000_000) {
        defaults = UserDefaults(suiteName: suite)!
        var timing = HeadsetSessionTiming()
        timing.ambientVerify = ambientVerify
        timing.operation = operationTimeout
        timing.acknowledgement = 10_000_000_000
        timing.equalizerDebounce = 5_000_000
        controller = HeadphonesController(transport: transport, preferences: defaults, timing: timing, pairedDevicesProvider: { [] })
    }
    func settle() async { for _ in 0..<20 { await Task.yield() } }
    func start() async {
        controller.connect(toAddress: "AA", name: "Mon casque Sony")
        transport.onEvent?(.opened)
        await settle()
        transport.ack(transport.commands[0])
        acknowledged = 1
        await settle()
        transport.receive([Opcode.initReply, 0, 0, 0, 0, 0, 0, 0])
        await settle()
        await drain()
        XCTAssertEqual(controller.connectionState, .connected)
    }
    func ackNext() async {
        guard transport.commands.count > acknowledged else { return XCTFail("No outstanding command") }
        let command = transport.commands[acknowledged]
        acknowledged += 1
        transport.ack(command)
        await settle()
    }
    func drain() async {
        for _ in 0..<80 {
            guard transport.commands.count > acknowledged else { return }
            await ackNext()
        }
        XCTFail("Queue did not drain")
    }
    func reportMode(bgm: Bool, cinema: Bool) async {
        transport.receive([Opcode.audioRetParam, 0x09, bgm ? 0 : 1, 1])
        transport.receive([Opcode.audioRetParam, 0x04, cinema ? 0 : 1])
        await settle()
    }
    func cleanUp() { controller.disconnect(); defaults.removePersistentDomain(forName: suite) }
}

@MainActor
final class CommandConfirmationTests: XCTestCase {
    func testAFlagAloneNeverInventsStandardOrCinema() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start()
        f.transport.receive([Opcode.audioRetParam, 0x09, 1, 1])
        await f.settle()
        XCTAssertNil(f.controller.listeningMode)
        f.transport.receive([Opcode.audioRetParam, 0x04, 0])
        await f.settle()
        XCTAssertEqual(f.controller.listeningMode, .cinema)
    }

    func testCinemaNeedsBothDeviceReportsNotJustAClickOrAcknowledgements() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start(); await f.reportMode(bgm: false, cinema: false)
        f.controller.setListeningMode(.cinema)
        XCTAssertEqual(f.controller.listeningMode, .standard)
        XCTAssertEqual(f.controller.requestedListeningMode, .cinema)
        XCTAssertEqual(f.controller.listeningModeOperation, .pending)
        await f.drain()
        XCTAssertEqual(f.controller.listeningModeOperation, .pending, "An ACK is not a physical setting report")
        f.transport.receive([Opcode.audioRetParam, 0x09, 1, 1])
        await f.settle()
        XCTAssertEqual(f.controller.listeningMode, .standard)
        XCTAssertEqual(f.controller.requestedListeningMode, .cinema)
        f.transport.receive([Opcode.audioRetParam, 0x04, 0])
        await f.settle()
        XCTAssertEqual(f.controller.listeningMode, .cinema)
        XCTAssertNil(f.controller.requestedListeningMode)
        XCTAssertEqual(f.controller.listeningModeOperation, .idle)
    }

    func testIntermediateMusicDisableDoesNotBounceThroughStandard() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start(); await f.reportMode(bgm: true, cinema: false)
        f.controller.setListeningMode(.cinema)
        f.transport.receive([Opcode.audioRetParam, 0x09, 1, 1])
        await f.settle()
        XCTAssertEqual(f.controller.listeningMode, .backgroundMusic)
        XCTAssertEqual(f.controller.requestedListeningMode, .cinema)
        // Before the Cinema write has even been sent, an old Cinema report cannot confirm.
        f.transport.receive([Opcode.audioRetParam, 0x04, 0])
        await f.settle()
        XCTAssertEqual(f.controller.listeningModeOperation, .pending)
        await f.ackNext()
        f.transport.receive([Opcode.audioRetParam, 0x04, 0])
        await f.settle()
        XCTAssertEqual(f.controller.listeningMode, .cinema)
        XCTAssertEqual(f.controller.listeningModeOperation, .idle)
    }

    func testRapidModeClicksReplaceObsoleteUnsentCommands() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start(); await f.reportMode(bgm: false, cinema: false)
        let start = f.transport.commands.count
        f.controller.setListeningMode(.cinema)
        f.controller.setListeningMode(.backgroundMusic)
        await f.drain()
        let payloads = Array(f.transport.commands.dropFirst(start).map(\.payload))
        XCTAssertFalse(payloads.contains(SonyCommands.buildUpmixCinemaSet(enabled: true)), "Unsent obsolete Cinema enable must be removed")
        XCTAssertTrue(payloads.contains(SonyCommands.buildBGMModeSet(enabled: true, roomSize: .middle)))
        await f.reportMode(bgm: true, cinema: false)
        XCTAssertEqual(f.controller.listeningMode, .backgroundMusic)
        XCTAssertNil(f.controller.requestedListeningMode)
    }

    func testUnconfirmedModeExpiresAndReturnsToLastKnownState() async {
        let f = ConfirmationFixture(operationTimeout: 35_000_000); defer { f.cleanUp() }
        await f.start(); await f.reportMode(bgm: false, cinema: false)
        f.controller.setListeningMode(.cinema)
        await f.drain()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(f.controller.requestedListeningMode)
        XCTAssertEqual(f.controller.listeningMode, .standard)
        guard case .failed = f.controller.listeningModeOperation else { return XCTFail("Missing reports must have a visible failure") }
        XCTAssertEqual(f.controller.connectionState, .connected, "A missing state report is different from an absent transport ACK")
    }

    func testAmbientGestureCoalescesQueuedValuesAndKeepsRequestedValueUntilMatchingReport() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start()
        let start = f.transport.commands.count
        for level in 0...20 { f.controller.setAmbientSound(.init(mode: .ambientSound, level: level)) }
        XCTAssertEqual(f.controller.requestedAmbientSound?.level, 20)
        XCTAssertNil(f.controller.ambientSound)
        await f.drain()
        let sets = f.transport.commands.dropFirst(start).filter { $0.payload.first == Opcode.ambientSoundControlSet }
        XCTAssertEqual(sets.count, 2, "Only the in-flight value and final queued value should be transmitted")
        f.transport.receive([Opcode.ambientSoundControlRet, 0x15, 1, 1, 1, 0, 3])
        await f.settle()
        XCTAssertEqual(f.controller.ambientSound?.level, 3)
        XCTAssertEqual(f.controller.requestedAmbientSound?.level, 20, "An older echo must not pull the control under the pointer")
        f.transport.receive([Opcode.ambientSoundControlRet, 0x15, 1, 1, 1, 0, 20])
        await f.settle()
        XCTAssertNil(f.controller.requestedAmbientSound)
        XCTAssertEqual(f.controller.ambientSound?.level, 20)
        XCTAssertEqual(f.controller.confirmedOperationRevision, 1)
        XCTAssertEqual(f.controller.commandOperation, .idle)
    }

    func testButtonPressIsShownImmediatelyAndThenVerifiedByARead() async {
        let f = ConfirmationFixture(ambientVerify: 20_000_000); defer { f.cleanUp() }
        await f.start()
        // Byte-for-byte the live XM6 forms: state read and button notification both
        // ride subtype 0x19, with the status byte (0x01) and two fixed middle bytes.
        f.transport.receive([Opcode.ambientSoundControlRet, 0x19, 1, 1, 0, 0, 1, 0, 0])
        await f.settle()
        XCTAssertEqual(f.controller.ambientSound?.mode, .noiseCancelling)
        let before = f.transport.commands.count
        // The physical button reports the new mode by itself: the panel follows it
        // at once instead of waiting for a read a wrong dialect never answers.
        f.transport.receive([Opcode.ambientSoundControlNotify, 0x19, 1, 1, 1, 0, 1, 0, 0])
        await f.settle()
        XCTAssertEqual(f.controller.ambientSound?.mode, .ambientSound)
        try? await Task.sleep(nanoseconds: 120_000_000)
        await f.settle()
        let reads = f.transport.commands.dropFirst(before).filter { $0.payload == SonyCommands.buildAmbientSoundGet(subtype: 0x19) }
        XCTAssertEqual(reads.count, 1, "A notification must trigger one confirming read")
        await f.drain()
        f.transport.receive([Opcode.ambientSoundControlRet, 0x19, 1, 1, 1, 0, 1, 0, 12])
        await f.settle()
        XCTAssertEqual(f.controller.ambientSound?.mode, .ambientSound)
        XCTAssertEqual(f.controller.ambientSound?.level, 12, "The read remains the final word")
    }

    func testEmptyPlaceholderReadNeverBecomesThePanelState() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start()
        // What the XM6 really answers for the probes it does not use.
        f.transport.receive([Opcode.ambientSoundControlRet, 0x17, 0, 0, 0, 0, 0])
        f.transport.receive([Opcode.ambientSoundControlRet, 0x15, 0, 0, 0, 0, 0])
        await f.settle()
        XCTAssertNil(f.controller.ambientSound, "An empty body carries no state: it must never show Désactivé")
        f.transport.receive([Opcode.ambientSoundControlRet, 0x19, 1, 1, 0, 0, 1, 0, 0])
        await f.settle()
        XCTAssertEqual(f.controller.ambientSound?.subtype, 0x19)
        XCTAssertEqual(f.controller.ambientSound?.mode, .noiseCancelling)
        // A plainer dialect can never displace the XM6's own.
        f.transport.receive([Opcode.ambientSoundControlRet, 0x15, 1, 1, 1, 0, 0, 9])
        await f.settle()
        XCTAssertEqual(f.controller.ambientSound?.subtype, 0x19)
        XCTAssertEqual(f.controller.ambientSound?.mode, .noiseCancelling)
    }

    func testRicherAmbientDialectDisplacesAnUnconfirmedPlainerReportAndNeverTheReverse() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start()
        // Until a write settles the dialect, the richer form may take over from a
        // plainer one (and an empty placeholder is already dropped by the decoder).
        f.transport.receive([Opcode.ambientSoundControlRet, 0x15, 1, 1, 1, 0, 9])
        await f.settle()
        f.transport.receive([Opcode.ambientSoundControlRet, 0x17, 1, 1, 0, 2, 0, 0])
        await f.settle()
        XCTAssertEqual(f.controller.ambientSound?.subtype, 0x17)
        XCTAssertEqual(f.controller.ambientSound?.mode, .noiseCancelling, "The plainer report must not own the panel")
        f.transport.receive([Opcode.ambientSoundControlRet, 0x15, 1, 0, 0, 0, 0])
        await f.settle()
        XCTAssertEqual(f.controller.ambientSound?.subtype, 0x17)
        XCTAssertEqual(f.controller.ambientSound?.mode, .noiseCancelling)
    }

    func testConfirmedAmbientDialectIsNotDisplacedByAnotherDialect() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start()
        f.transport.receive([Opcode.ambientSoundControlRet, 0x15, 1, 1, 0, 0, 0])
        await f.settle()
        f.controller.setAmbientSound(.init(mode: .ambientSound, level: 12))
        await f.drain()
        f.transport.receive([Opcode.ambientSoundControlRet, 0x15, 1, 1, 1, 0, 12])
        await f.settle()
        XCTAssertNil(f.controller.requestedAmbientSound)
        // Another dialect answering a later probe is an echo: the write settled it.
        f.transport.receive([Opcode.ambientSoundControlRet, 0x17, 1, 1, 0, 2, 0, 0])
        await f.settle()
        XCTAssertEqual(f.controller.ambientSound?.subtype, 0x15)
        XCTAssertEqual(f.controller.ambientSound?.mode, .ambientSound)
    }

    func testAmbientWriteSpeaksTheDialectAndShapeTheHeadsetUses() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start()
        // The XM6 reports its state on 0x19 with two fixed middle bytes, while the
        // caller carries a plain state: the write must follow the device exactly,
        // including those bytes it stores verbatim.
        f.transport.receive([Opcode.ambientSoundControlRet, 0x19, 1, 1, 0, 0, 1, 0, 0])
        await f.settle()
        f.controller.setAmbientSound(.init(mode: .ambientSound, level: 12))
        await f.drain()
        let set = f.transport.commands.last(where: { $0.payload.first == Opcode.ambientSoundControlSet })?.payload
        XCTAssertEqual(set, [Opcode.ambientSoundControlSet, 0x19, 0x01, 0x01, 0x01, 0x00, 0x01, 0x00, 0x0c])
    }

    func testUnconfirmedAmbientWriteRetriesOnceOnTheOtherDialectTheHeadsetAnswers() async {
        let f = ConfirmationFixture(operationTimeout: 300_000_000); defer { f.cleanUp() }
        await f.start()
        f.transport.receive([Opcode.ambientSoundControlRet, 0x17, 1, 1, 0, 2, 0, 15])
        await f.settle()
        f.transport.receive([Opcode.ambientSoundControlRet, 0x15, 1, 1, 0, 0, 0])
        await f.settle()
        XCTAssertEqual(f.controller.ambientSound?.subtype, 0x17)
        f.controller.setAmbientSound(.init(mode: .ambientSound, level: 12))
        await f.drain()
        // The headset reads the wind dialect but only accepts the plain one: an
        // ignored write is silent, so one bounded retry is the way to discover it.
        try? await Task.sleep(nanoseconds: 350_000_000)
        await f.settle()
        XCTAssertEqual(f.controller.commandOperation, .pending, "The retry keeps the request alive")
        XCTAssertEqual(f.controller.requestedAmbientSound?.mode, .ambientSound)
        let sets = f.transport.commands.filter { $0.payload.first == Opcode.ambientSoundControlSet }
        XCTAssertEqual(sets.last?.payload, [Opcode.ambientSoundControlSet, 0x15, 0x01, 0x01, 0x01, 0x00, 0x0c])
        await f.drain()
        f.transport.receive([Opcode.ambientSoundControlRet, 0x15, 1, 1, 1, 0, 12])
        await f.settle()
        XCTAssertNil(f.controller.requestedAmbientSound)
        XCTAssertEqual(f.controller.ambientSound?.subtype, 0x15)
        XCTAssertEqual(f.controller.commandOperation, .idle)
    }

    func testRoomChangeCannotReenableMusicAfterSelectingCinema() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start(); await f.reportMode(bgm: true, cinema: false)
        // Hold one unrelated command in flight so the room write remains queued.
        f.controller.sendRaw([0xAA])
        f.controller.setBGMRoomSize(.large)
        f.controller.setListeningMode(.cinema)
        XCTAssertNil(f.controller.requestedBGMRoomSize)
        XCTAssertEqual(f.controller.commandOperation, .idle, "Cancelling a queued room request must end its progress status")
        XCTAssertEqual(f.controller.confirmedOperationRevision, 0, "Cancellation must never announce a confirmation to VoiceOver")
        let start = f.transport.commands.count
        await f.drain()
        XCTAssertFalse(f.transport.commands.dropFirst(start).contains {
            $0.payload == SonyCommands.buildBGMModeSet(enabled: true, roomSize: .large)
        })
    }

    func testEqualizerGestureDebouncesAndDoesNotAcceptStaleCurve() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start()
        let last = Array(repeating: 4, count: SonyCommands.defaultBandCount)
        for level in 0...4 { f.controller.setEqualizerBands(Array(repeating: level, count: SonyCommands.defaultBandCount)) }
        XCTAssertEqual(f.controller.requestedEqualizer?.bands, last)
        try? await Task.sleep(nanoseconds: 30_000_000)
        await f.drain()
        XCTAssertEqual(f.controller.requestedEqualizer?.bands, last)
        XCTAssertNil(f.controller.equalizer)
        let stale: [UInt8] = [Opcode.equalizerRet, 0x04, EqualizerPreset.custom.rawValue, 10] + Array(repeating: 7, count: 10)
        f.transport.receive(stale)
        await f.settle()
        XCTAssertEqual(f.controller.equalizer?.bands, Array(repeating: 1, count: 10))
        XCTAssertEqual(f.controller.requestedEqualizer?.bands, last)
        f.transport.receive([Opcode.equalizerRet, 0x04, EqualizerPreset.custom.rawValue, 10] + Array(repeating: 10, count: 10))
        await f.settle()
        XCTAssertNil(f.controller.requestedEqualizer)
        XCTAssertEqual(f.controller.equalizer?.bands, last)
    }

    func testNoiseCancellationConfirmationDoesNotRequireAnIrrelevantAmbientLevel() async {
        let f = ConfirmationFixture(); defer { f.cleanUp() }
        await f.start()
        f.controller.setAmbientSound(.init(mode: .noiseCancelling, level: 15))
        await f.drain()
        f.transport.receive([Opcode.ambientSoundControlRet, 0x15, 1, 1, 0, 0, 0])
        await f.settle()
        XCTAssertEqual(f.controller.ambientSound?.mode, .noiseCancelling)
        XCTAssertNil(f.controller.requestedAmbientSound)
        XCTAssertEqual(f.controller.commandOperation, .idle)
    }
}

final class HeadsetCommandQueueTests: XCTestCase {
    func testLatestQueuedValueReplacesOldValueButNeverChangesInFlight() {
        var queue = HeadsetCommandQueue()
        let old = HeadsetCommandQueue.Command([1], group: "ambient", isWrite: true)
        queue.replace(group: "ambient", with: [old])
        XCTAssertEqual(queue.beginNext()?.payload, [1])
        queue.replace(group: "ambient", with: [.init([2], group: "ambient", isWrite: true)])
        queue.replace(group: "ambient", with: [.init([3], group: "ambient", isWrite: true)])
        XCTAssertEqual(queue.inFlight?.payload, [1])
        XCTAssertEqual(queue.pending.map(\.payload), [[3]])
        queue.acknowledge()
        XCTAssertEqual(queue.beginNext()?.payload, [3])
    }

    func testWriteBatchGoesBeforeBackgroundReadsAndKeepsItsOrder() {
        var queue = HeadsetCommandQueue()
        queue.append(.init([9], group: "read.battery"))
        let id = UUID()
        queue.replace(group: "listening", with: [
            .init([1], group: "listening", intent: id, isWrite: true),
            .init([2], group: "listening", intent: id, isWrite: true),
            .init([3], group: "listening", intent: id)
        ])
        XCTAssertEqual(queue.pending.map(\.payload), [[1], [2], [3], [9]])
    }

    func testRepeatedRefreshDoesNotGrowIdenticalPendingReads() {
        var queue = HeadsetCommandQueue()
        for _ in 0..<100 { queue.append(.init([9], group: "read.battery")) }
        XCTAssertEqual(queue.pending.count, 1)
        queue.reset()
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertNil(queue.inFlight)
    }
}

final class SonyFrameIntegrityTests: XCTestCase {
    func testEveryByteValueRoundTripsIncludingEscapedDelimiters() {
        let payload = Array(UInt8.min...UInt8.max)
        let original = SonyMessage(type: .command1, sequenceNumber: 1, payload: payload)
        XCTAssertEqual(SonyMessage.decode(rawFrame: original.encode()), original)
    }

    func testCorruptChecksumIsRejectedAndNextFrameRecovers() {
        let frame = SonyMessage(type: .command2, sequenceNumber: 0, payload: [1, 2, 3])
        var corrupt = frame.encode()
        corrupt[corrupt.count - 2] ^= 1
        let parser = FrameParser()
        XCTAssertEqual(parser.feed(corrupt + frame.encode()), [frame])
    }

    func testTruncatedFrameDoesNotSwallowTheFollowingValidFrame() {
        let valid = SonyMessage(type: .command1, sequenceNumber: 0, payload: [1, 2, 3])
        let parser = FrameParser()
        XCTAssertEqual(parser.feed([SonyMessage.header, 0x0c, 0x00, 0x00] + valid.encode()), [valid])
    }

    func testInvalidListeningFlagsAreNotInterpretedAsDisabled() {
        XCTAssertNil(SonyCommands.decodeBGMMode([Opcode.audioRetParam, 0x09, 0xFF, 1]))
        XCTAssertNil(SonyCommands.decodeUpmixCinema([Opcode.audioRetParam, 0x04, 0xFF]))
    }

    func testFragmentedFrameAndBackToBackFrames() {
        let one = SonyMessage(type: .command1, sequenceNumber: 0, payload: [0x3c, 0x3d, 0x3e])
        let two = SonyMessage(type: .ack, sequenceNumber: 1, payload: [])
        let parser = FrameParser()
        let bytes = one.encode()
        XCTAssertTrue(parser.feed(Array(bytes.prefix(5))).isEmpty)
        XCTAssertEqual(parser.feed(Array(bytes.dropFirst(5)) + two.encode()), [one, two])
    }
}
