import XCTest
@testable import SonyHeadphonesKit

/// Session tests intentionally never instantiate RFCOMMConnection or inspect the
/// Mac's paired devices. Every event and packet comes from this in-memory double.
private final class SessionTransport: HeadphonesTransport {
    var onEvent: ((RFCOMMConnectionEvent) -> Void)?
    var addresses: [String] = []
    var writes: [SonyMessage] = []
    var disconnectCount = 0

    func connect(toDeviceAddress address: String) { addresses.append(address) }
    func disconnect() { disconnectCount += 1 }
    func write(_ bytes: [UInt8]) {
        guard let message = SonyMessage.decode(rawFrame: bytes) else {
            XCTFail("Controller wrote an invalid Sony frame")
            return
        }
        writes.append(message)
    }
    func emit(_ event: RFCOMMConnectionEvent) { onEvent?(event) }
    func report(_ payload: [UInt8]) {
        emit(.dataReceived(SonyMessage(type: .command1, sequenceNumber: 0, payload: payload).encode()))
    }
    var commands: [SonyMessage] { writes.filter { $0.type != .ack } }
}

@MainActor
private final class SessionFixture {
    let transport = SessionTransport()
    let defaults: UserDefaults
    let controller: HeadphonesController
    private let suite = "XMControl.SessionTests.\(UUID().uuidString)"
    private var acknowledged = 0

    init(timing: HeadsetSessionTiming = .init(connect: 10_000_000_000, handshake: 10_000_000_000,
                                            acknowledgement: 10_000_000_000, initialState: 10_000_000_000,
                                            operation: 10_000_000_000, equalizerDebounce: 10_000_000_000)) {
        defaults = UserDefaults(suiteName: suite)!
        controller = HeadphonesController(transport: transport, preferences: defaults,
                                          timing: timing, pairedDevicesProvider: { [] })
    }
    func cleanUp() {
        controller.disconnect()
        defaults.removePersistentDomain(forName: suite)
    }
    func settle() async {
        // Transport callbacks enter a MainActor Task. Yield rather than sleeping
        // arbitrary wall-clock delays for ordinary event processing.
        for _ in 0..<16 { await Task.yield() }
    }
    func open() async {
        controller.connect(toAddress: "AA-BB-CC-DD-EE-FF", name: "Mon casque Sony")
        transport.emit(.opened)
        await settle()
    }
    func establish() async {
        await open()
        transport.report([Opcode.initReply, 0, 0, 0, 0, 0, 0, 0])
        await settle()
        acknowledgeHandshake()
        await settle()
        XCTAssertEqual(controller.connectionState, .connected)
    }
    func acknowledgeHandshake() {
        let initial = transport.commands.last { $0.payload == SonyCommands.buildInit() }!
        transport.emit(.dataReceived(SonyMessage(type: .ack, sequenceNumber: initial.sequenceNumber ^ 1, payload: []).encode()))
    }
    func acknowledgeInitialReads() async {
        // The init request was acknowledged during establish(). Acknowledge queued
        // queries one by one, never invent a response value.
        acknowledged = max(acknowledged, 1)
        for _ in 0..<40 {
            let commands = transport.commands
            guard commands.count > acknowledged else { return }
            let message = commands[acknowledged]
            acknowledged += 1
            transport.emit(.dataReceived(SonyMessage(type: .ack,
                                                     sequenceNumber: message.sequenceNumber ^ 1,
                                                     payload: []).encode()))
            await settle()
        }
        XCTFail("Initial state queries did not drain")
    }
}

@MainActor
final class HeadsetSessionTests: XCTestCase {
    func testOpeningTransportDoesNotRememberHeadsetUntilRecognizedSonyHandshake() async {
        let fixture = SessionFixture()
        defer { fixture.cleanUp() }
        await fixture.open()
        XCTAssertEqual(fixture.controller.connectionState, .initializing)
        XCTAssertNil(fixture.defaults.string(forKey: "personalHeadsetAddress"))
        XCTAssertEqual(fixture.transport.commands.map(\.payload), [SonyCommands.buildInit()])

        fixture.transport.report([Opcode.initReply, 0, 0, 0, 0, 0, 0, 0])
        await fixture.settle()
        XCTAssertEqual(fixture.controller.connectionState, .initializing, "A valid reply still needs the init ACK")
        XCTAssertNil(fixture.defaults.string(forKey: "personalHeadsetAddress"))
        fixture.acknowledgeHandshake()
        await fixture.settle()
        XCTAssertEqual(fixture.controller.connectionState, .connected)
        XCTAssertEqual(fixture.controller.protocolVersion, .v2)
        XCTAssertEqual(fixture.defaults.string(forKey: "personalHeadsetAddress"), "AA-BB-CC-DD-EE-FF")
        XCTAssertEqual(fixture.defaults.string(forKey: "personalHeadsetName"), "Mon casque Sony")
    }

    func testInvalidHandshakeFailsWithoutReplacingRememberedHeadset() async {
        let fixture = SessionFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set("PREVIOUS", forKey: "personalHeadsetAddress")
        await fixture.open()
        fixture.transport.report([Opcode.initReply, 0])
        await fixture.settle()
        guard case .failed = fixture.controller.connectionState else {
            return XCTFail("Unrecognized handshake must fail")
        }
        XCTAssertEqual(fixture.defaults.string(forKey: "personalHeadsetAddress"), "PREVIOUS")
        XCTAssertNil(fixture.transport.onEvent)
        XCTAssertEqual(fixture.transport.commands.count, 1)
    }

    func testFragmentedHandshakeOnlyInitializesAfterCompleteValidatedFrame() async {
        let fixture = SessionFixture()
        defer { fixture.cleanUp() }
        await fixture.open()
        let bytes = SonyMessage(type: .command1, sequenceNumber: 0,
                               payload: [Opcode.initReply, 0, 0, 0, 0, 0, 0, 0]).encode()
        // ACK first is the reverse ordering of the other successful handshake
        // test; it must precede the fragmented reply on the byte stream.
        fixture.acknowledgeHandshake()
        await fixture.settle()
        fixture.transport.emit(.dataReceived(Array(bytes.prefix(6))))
        await fixture.settle()
        XCTAssertEqual(fixture.controller.connectionState, .initializing)
        XCTAssertNil(fixture.defaults.string(forKey: "personalHeadsetAddress"))
        fixture.transport.emit(.dataReceived(Array(bytes.dropFirst(6))))
        await fixture.settle()
        XCTAssertEqual(fixture.controller.connectionState, .connected)
        XCTAssertNotNil(fixture.defaults.string(forKey: "personalHeadsetAddress"))
    }

    func testInitialAmbientOffAndZeroRemainReadOnly() async {
        let fixture = SessionFixture()
        defer { fixture.cleanUp() }
        await fixture.establish()
        fixture.transport.report([Opcode.ambientSoundControlRet, 0x15, 1, 0, 0, 0, 0])
        await fixture.settle()
        await fixture.acknowledgeInitialReads()
        XCTAssertEqual(fixture.controller.ambientSound?.mode, .off)
        XCTAssertEqual(fixture.controller.ambientSound?.level, 0)
        XCTAssertFalse(fixture.transport.commands.contains { $0.payload.first == Opcode.ambientSoundControlSet },
                       "Connecting and reading state must never enable ANC or replace ambient zero")
        XCTAssertNil(fixture.controller.requestedAmbientSound)
    }

    func testClosedSessionCancelsPendingWorkAndDiscardsReports() async {
        var timing = HeadsetSessionTiming()
        timing.initialState = 35_000_000
        timing.acknowledgement = 10_000_000_000
        let fixture = SessionFixture(timing: timing)
        defer { fixture.cleanUp() }
        await fixture.establish()
        fixture.controller.setListeningMode(.cinema)
        XCTAssertEqual(fixture.controller.requestedListeningMode, .cinema)
        fixture.transport.emit(.closed)
        await fixture.settle()
        let writesAfterClose = fixture.transport.writes.count
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(fixture.transport.onEvent)
        XCTAssertNil(fixture.controller.requestedListeningMode)
        XCTAssertNil(fixture.controller.battery)
        XCTAssertFalse(fixture.controller.initialStateTimedOut, "Cancelled initial-state deadline must not fire")
        XCTAssertEqual(fixture.transport.writes.count, writesAfterClose)
        XCTAssertEqual(fixture.controller.connectionState, .connecting, "A dropped link is reconnected, not abandoned")
    }

    func testTransportFailureCancelsQueuedCommandsAndReconnects() async {
        let fixture = SessionFixture()
        defer { fixture.cleanUp() }
        await fixture.establish()
        fixture.controller.setListeningMode(.cinema)
        fixture.transport.emit(.failed("simulated transport error"))
        await fixture.settle()
        XCTAssertEqual(fixture.controller.connectionState, .connecting)
        XCTAssertEqual(fixture.controller.lastError, "simulated transport error")
        XCTAssertNil(fixture.controller.requestedListeningMode)
        XCTAssertEqual(fixture.controller.listeningModeOperation, .failed("simulated transport error"))
        let writes = fixture.transport.writes.count
        fixture.controller.sendRaw([0xAA])
        await fixture.settle()
        XCTAssertEqual(fixture.transport.writes.count, writes)
        XCTAssertNil(fixture.transport.onEvent)
    }

    func testCallbackFromPreviousSessionCannotCloseOrMutateReconnection() async {
        let fixture = SessionFixture()
        defer { fixture.cleanUp() }
        await fixture.establish()
        let oldCallback = fixture.transport.onEvent
        fixture.controller.disconnect()
        await fixture.establish()
        let commands = fixture.transport.commands.count
        oldCallback?(.closed)
        oldCallback?(.opened)
        oldCallback?(.dataReceived(SonyMessage(type: .command1, sequenceNumber: 0,
                                              payload: [Opcode.batteryLevelReply, 0, 99, 0]).encode()))
        await fixture.settle()
        XCTAssertEqual(fixture.controller.connectionState, .connected)
        XCTAssertNil(fixture.controller.battery)
        XCTAssertEqual(fixture.transport.commands.count, commands)
    }

    func testMissingAcknowledgementTerminatesSessionWithoutSendingNextCommand() async {
        var timing = HeadsetSessionTiming()
        timing.acknowledgement = 35_000_000
        let fixture = SessionFixture(timing: timing)
        defer { fixture.cleanUp() }
        await fixture.establish()
        fixture.controller.setListeningMode(.cinema)
        let commands = fixture.transport.commands.count
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(fixture.controller.connectionState, .connecting, "Missing ACK drops the link and reconnects")
        XCTAssertEqual(fixture.transport.commands.count, commands, "Never advance a queue after an ambiguous timeout")
        XCTAssertNil(fixture.transport.onEvent)
        XCTAssertNil(fixture.controller.requestedListeningMode)
    }

    func testLostLinkReconnectsToTheSameHeadsetAutomatically() async {
        var timing = HeadsetSessionTiming()
        timing.reconnectDelays = [10_000_000]
        let fixture = SessionFixture(timing: timing)
        defer { fixture.cleanUp() }
        await fixture.establish()
        fixture.transport.emit(.closed)
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(fixture.transport.addresses, ["AA-BB-CC-DD-EE-FF", "AA-BB-CC-DD-EE-FF"])
        XCTAssertEqual(fixture.controller.connectionState, .connecting)
        fixture.transport.emit(.opened)
        await fixture.settle()
        XCTAssertEqual(fixture.controller.connectionState, .initializing)
    }

    func testSilentHeadsetIsDetectedAndReconnected() async {
        var timing = HeadsetSessionTiming()
        timing.heartbeat = 20_000_000
        timing.silence = 80_000_000
        timing.acknowledgement = 10_000_000_000
        timing.reconnectDelays = [10_000_000]
        let fixture = SessionFixture(timing: timing)
        defer { fixture.cleanUp() }
        await fixture.establish()
        await fixture.acknowledgeInitialReads()
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertGreaterThanOrEqual(fixture.transport.addresses.count, 2,
                                    "A headset silent for longer than the limit must be reconnected")
        XCTAssertTrue(fixture.transport.commands.contains { $0.payload == SonyCommands.buildBatteryGet() },
                      "The liveness probe must go out while connected")
    }

    func testReconnectGivesUpAfterTheLastAttempt() async {
        var timing = HeadsetSessionTiming()
        timing.reconnectDelays = [5_000_000]
        let fixture = SessionFixture(timing: timing)
        defer { fixture.cleanUp() }
        await fixture.establish()
        fixture.transport.emit(.closed)
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(fixture.transport.addresses.count, 2)
        fixture.transport.emit(.closed)
        await fixture.settle()
        guard case .failed = fixture.controller.connectionState else {
            return XCTFail("After the last attempt the failure must reach the user")
        }
        XCTAssertEqual(fixture.transport.addresses.count, 2, "No attempt beyond the configured list")
    }

    func testUserDisconnectStopsPendingReconnection() async {
        var timing = HeadsetSessionTiming()
        timing.reconnectDelays = [50_000_000]
        let fixture = SessionFixture(timing: timing)
        defer { fixture.cleanUp() }
        await fixture.establish()
        fixture.transport.emit(.closed)
        fixture.controller.disconnect()
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(fixture.transport.addresses.count, 1, "Disconnect must cancel the scheduled retry")
        XCTAssertEqual(fixture.controller.connectionState, .disconnected)
    }

    func testAllWritesAreRejectedOutsideConnectedSession() async {
        let fixture = SessionFixture()
        defer { fixture.cleanUp() }
        fixture.controller.setListeningMode(.cinema)
        fixture.controller.setAmbientSound(.init(mode: .ambientSound, level: 0))
        fixture.controller.sendRaw([0xAA])
        XCTAssertTrue(fixture.transport.writes.isEmpty)
        XCTAssertNil(fixture.controller.requestedAmbientSound)
        XCTAssertNil(fixture.controller.requestedListeningMode)
        await fixture.open()
        let initialWrites = fixture.transport.writes.count
        fixture.controller.setListeningMode(.backgroundMusic)
        fixture.controller.sendRaw([0xAA])
        XCTAssertEqual(fixture.transport.writes.count, initialWrites)
    }

    func testStateDeadlineMarksEveryMissingFeatureWithoutInventingValues() async {
        var timing = HeadsetSessionTiming()
        timing.initialState = 35_000_000
        timing.acknowledgement = 10_000_000_000
        let fixture = SessionFixture(timing: timing)
        defer { fixture.cleanUp() }
        await fixture.establish()
        XCTAssertEqual(fixture.controller.availability(for: .equalizer), .loading)
        XCTAssertEqual(fixture.controller.availability(for: .listeningMode), .loading)
        fixture.transport.report([Opcode.batteryLevelReply, 0, 73, 0])
        await fixture.settle()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(fixture.controller.initialStateTimedOut)
        XCTAssertEqual(fixture.controller.availability(for: .battery), .available)
        for feature in HeadsetFeature.allCases where feature != .battery {
            XCTAssertEqual(fixture.controller.availability(for: feature), .notReported, "Missing feature: \(feature)")
        }
        XCTAssertNil(fixture.controller.equalizer)
        XCTAssertNil(fixture.controller.listeningMode)
        XCTAssertEqual(fixture.controller.connectionState, .connected)
    }
}
