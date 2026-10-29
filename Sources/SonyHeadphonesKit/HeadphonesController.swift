import Foundation
import Combine

/// Session state on the main actor; byte layouts remain in SonyCommands.
/// Reported settings and requested settings are deliberately separate: an ACK only
/// acknowledges transport, while a decoded device report confirms a setting.
@MainActor
public final class HeadphonesController: ObservableObject {
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var deviceName: String?
    @Published public private(set) var protocolVersion: ProtocolVersion = .unknown
    @Published public private(set) var pairedDevices: [PairedDeviceInfo] = []
    @Published public private(set) var ambientSound: AmbientSoundState?
    @Published public private(set) var battery: BatteryStatus?
    @Published public private(set) var speakToChatEnabled: Bool?
    @Published public private(set) var speakToChatConfig: SpeakToChatConfigState?
    @Published public private(set) var automaticPowerOff: AutomaticPowerOffMode?
    @Published public private(set) var pauseWhenTakenOff: Bool?
    @Published public private(set) var equalizer: EqualizerState?
    @Published public private(set) var listeningMode: ListeningMode?
    @Published public private(set) var bgmRoomSize: BGMRoomSize?
    @Published public private(set) var devices: [MultipointDevice]?
    @Published public private(set) var lastError: String?
    @Published public private(set) var initialStateTimedOut = false

    @Published public private(set) var requestedListeningMode: ListeningMode?
    @Published public private(set) var listeningModeOperation: CommandOperation = .idle
    @Published public private(set) var commandOperation: CommandOperation = .idle
    @Published public private(set) var sourceOperation: CommandOperation = .idle
    @Published public private(set) var requestedSourceDeviceId: String?
    @Published public private(set) var confirmedOperationRevision = 0
    @Published public private(set) var requestedAmbientSound: AmbientSoundState?
    @Published public private(set) var requestedEqualizer: EqualizerState?
    @Published public private(set) var requestedBGMRoomSize: BGMRoomSize?
    @Published public private(set) var requestedSpeakToChatEnabled: Bool?
    @Published public private(set) var requestedSpeakToChatConfig: SpeakToChatConfigState?
    @Published public private(set) var requestedAutomaticPowerOff: AutomaticPowerOffMode?
    @Published public private(set) var requestedPauseWhenTakenOff: Bool?

    @Published public var protocolLoggingEnabled: Bool {
        didSet {
            preferences.defaults.set(protocolLoggingEnabled, forKey: "protocolLoggingEnabled")
            protocolLog.isEnabled = protocolLoggingEnabled
        }
    }

    public var personalHeadset: PairedDeviceInfo? {
        PersonalHeadsetSelection.preferred(
            in: pairedDevices,
            rememberedAddress: preferences.address,
            customName: preferences.customDisplayName,
            preferredModel: preferences.modelPreference.model
        )
    }
    /// Name shown in the UI. Priority: user-typed display name, live Bluetooth
    /// name, remembered name, then a generic fallback. No personal data here:
    /// the default is the same for everyone until they personalize it.
    public var personalHeadsetName: String {
        if let custom = preferences.customDisplayName { return custom }
        return personalHeadset?.name ?? preferences.name ?? "Mon casque"
    }
    /// Display name editable in Preferences (free text, e.g. "Casque de Marie").
    public var customDisplayName: String? { preferences.customDisplayName }
    public var ownerName: String? { preferences.ownerName }
    public var modelPreference: HeadsetModelPreference { preferences.modelPreference }
    /// All paired XM candidates, for the headset picker when several match.
    public var xmCandidates: [PairedDeviceInfo] {
        pairedDevices.filter { PersonalHeadsetSelection.isXMDevice(named: $0.name) }
    }
    /// Detected generation from the live, remembered or custom name.
    public var detectedModel: HeadsetModel? {
        let names = [personalHeadset?.name, deviceName, preferences.customDisplayName, preferences.name].compactMap { $0 }
        for name in names {
            if let model = HeadsetModel.detect(fromName: name) { return model }
        }
        return preferences.modelPreference.model
    }
    /// Label shown under the display name, e.g. "WH-1000XM5".
    public var modelLabel: String { detectedModel?.fullLabel ?? "WH-1000X" }
    public var rawMessageHandler: ((SonyMessageType, [UInt8]) -> Void)?

    private let preferences: PersonalHeadsetPreferences
    private let connection: HeadphonesTransport
    private let pairedDevicesProvider: () -> [PairedDeviceInfo]
    private let timing: HeadsetSessionTiming
    private let frameParser = FrameParser()
    private let protocolLog = ProtocolLog()
    private var session = UUID()
    private var sequenceNumber: UInt8 = 0
    private var commandQueue = HeadsetCommandQueue()
    private var ackTimeoutTask: Task<Void, Never>?
    private var initRetryTask: Task<Void, Never>?
    private var stateTimeoutTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    private var equalizerWriteTask: Task<Void, Never>?
    private var ambientRefreshTask: Task<Void, Never>?
    /// The Ambient Sound Control dialect (subtype byte) whose reports are shown.
    ///
    /// Sony reuses the same opcodes for several dialects told apart by the
    /// subtype byte. A live WH-1000XM6 capture settled which one this firmware
    /// speaks: **0x19** carries both the read (`67 19 …`) and the button
    /// notification (`69 19 …`), while 0x15/0x16/0x17/0x18 are answered with an
    /// empty placeholder body that carries no state. Nothing declares the dialect
    /// up front, so it is never "whoever answers first": an unsolicited
    /// notification always wins (the device speaking on its own), a write the
    /// device confirms pins it for good, and until then the richest dialect may
    /// take over from a plainer one.
    private var ambientSubtype: UInt8?
    /// Last report seen per dialect, so a takeover or a retry has real data.
    private var ambientReports: [UInt8: AmbientSoundState] = [:]
    /// Dialect pinned by a write the device echoed back and read back.
    private var ambientConfirmedSubtype: UInt8?
    /// Dialects the pending change has already been written to (bounds the retry).
    private var ambientWrittenSubtypes: Set<UInt8> = []
    /// Probed/observed dialects, richest first.
    private static let ambientSubtypeOrder: [UInt8] = [0x19, 0x17, 0x15, 0x22]
    private var initRetryCount = 0
    private var connectTarget: (address: String, name: String?)?
    /// True from the user's connect request until they disconnect or give up, so a
    /// dropped link is recovered rather than ending the session.
    private var wantsConnection = false
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var devicePollTask: Task<Void, Never>?
    /// Background join monitor: polls the Mac Bluetooth link so a headset
    /// connected via Réglages Système is picked up without another click.
    private var linkMonitorTask: Task<Void, Never>?
    /// Set by an explicit Déconnecter: while the Mac link stays up, the monitor
    /// must not reconnect behind the user's back. Cleared on the next manual
    /// connect, or as soon as the Mac link drops.
    private var suppressAutoReconnect = false
    /// Last source confirmed after an explicit Utiliser, and when. If the active
    /// source moves elsewhere inside the steal window without a new request,
    /// the other device took the playback back on its own.
    private var lastConfirmedSourceId: String?
    private var lastSourceSwitchAt: UInt64 = 0
    private static let stealWindow: UInt64 = 30_000_000_000
    /// Monotonic time of the last byte received from the headset.
    private var lastInboundAt: UInt64 = 0
    private var handshakeInFlight = false
    private var pendingProtocolVersion: ProtocolVersion?
    private var bgmEnabled: Bool?
    private var cinemaEnabled: Bool?
    private var modeBGMDispatched = false
    private var modeCinemaDispatched = false
    private var modeSawBGM = false
    private var modeSawCinema = false

    private struct PendingChange {
        let id: UUID
        let matches: (HeadphonesEvent) -> Bool
        var started = false
        var timeout: Task<Void, Never>?
    }
    private var changes: [String: PendingChange] = [:]
    private static let modeGroup = "listening"
    private static let sourceGroup = "source"

    public convenience init(preferences: UserDefaults = .standard) {
        self.init(transport: RFCOMMConnection(), preferences: preferences,
                  pairedDevicesProvider: RFCOMMConnection.pairedDevices)
    }

    init(transport: HeadphonesTransport, preferences: UserDefaults,
         timing: HeadsetSessionTiming = .init(),
         pairedDevicesProvider: @escaping () -> [PairedDeviceInfo]) {
        self.connection = transport
        self.preferences = PersonalHeadsetPreferences(defaults: preferences)
        self.pairedDevicesProvider = pairedDevicesProvider
        self.timing = timing
        protocolLoggingEnabled = preferences.bool(forKey: "protocolLoggingEnabled")
        protocolLog.isEnabled = protocolLoggingEnabled
    }

    /// Reads the paired devices off the main thread. IOBluetooth can wait for the
    /// system's Bluetooth permission answer; a synchronous read on the main thread
    /// froze the whole app at launch until that answer came.
    public func refreshPairedDevices() {
        Task { @MainActor in _ = await reloadPairedDevices() }
    }

    private func reloadPairedDevices() async -> [PairedDeviceInfo] {
        let provider = pairedDevicesProvider
        let devices = await Task.detached(priority: .userInitiated) { provider() }.value
        publishIfChanged(\.pairedDevices, devices)
        return devices
    }

    /// `@Published` notifies every observer on each assignment, equal value or not.
    /// Heartbeat and ambient replies repeat the same state every few seconds, so only
    /// a real change is published.
    private func publishIfChanged<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<HeadphonesController, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    private var isBusyForAutoConnect: Bool {
        // While waiting to reconnect, "connect now" must not be refused as busy.
        guard reconnectTask == nil else { return false }
        switch connectionState {
        case .connected, .connecting, .initializing: return true
        default: return false
        }
    }

    public func autoConnect() {
        suppressAutoReconnect = false
        guard !isBusyForAutoConnect else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.reloadPairedDevices()
            guard !self.isBusyForAutoConnect else { return }
            if let headset = self.personalHeadset {
                self.connect(toAddress: headset.id, name: headset.name)
                return
            }
            // The paired list can be stale right after pairing: fall back to the
            // remembered address so Se connecter still drives the Mac Bluetooth
            // connection instead of only reporting "not paired".
            if let address = self.preferences.address {
                self.connect(toAddress: address, name: self.preferences.name)
                return
            }
            self.finishSession(error: self.noHeadsetError())
        }
    }

    public func connect(toAddress address: String, name: String?) {
        suppressAutoReconnect = false
        if reconnectTask == nil, connectTarget?.address == address,
           connectionState == .connected || connectionState == .connecting || connectionState == .initializing { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        wantsConnection = true
        connectTarget = (address, name)
        attemptConnect()
    }

    private func attemptConnect() {
        guard let target = connectTarget else { return }
        connection.onEvent = nil
        connection.disconnect()
        resetSession()
        let current = session
        connection.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.session == current else { return }
                self.handle(event)
            }
        }
        deviceName = target.name
        lastError = nil
        connectionState = .connecting
        protocolLog.startSession(deviceName: target.name)
        connection.connect(toDeviceAddress: target.address)
        connectTimeoutTask = deadline(timing.connect) { [weak self] in self?.connectExpired() }
    }

    private func connectExpired() {
        guard connectionState == .connecting || connectionState == .initializing else { return }
        linkLost(L("Le casque ne répond pas.", "The headset is not responding."))
    }

    /// The link dropped or went silent. While the user still wants the headset, wait
    /// a growing pause and connect again; only after the last attempt does the failure
    /// reach the user. The session keeps its target, so the retry needs no user action.
    private func linkLost(_ reason: String) {
        guard wantsConnection else { finishSession(error: reason); return }
        guard reconnectTask == nil else { return }
        guard reconnectAttempts < timing.reconnectDelays.count else {
            finishSession(error: reason + L(" Vérifiez qu’il est allumé et à portée, puis réessayez.", " Check that it is on and nearby, then try again."))
            return
        }
        let delay = timing.reconnectDelays[reconnectAttempts]
        reconnectAttempts += 1
        lastError = reason
        let modePending = requestedListeningMode != nil
        let sourcePending = requestedSourceDeviceId != nil
        let otherPending = changes.keys.contains { $0 != Self.modeGroup && $0 != Self.sourceGroup }
        connection.onEvent = nil
        connection.disconnect()
        resetSession()
        // A change in flight dies with the link; say so rather than dropping it silently.
        // Set after resetSession, which clears the operation state.
        if modePending { listeningModeOperation = .failed(reason) }
        if sourcePending { sourceOperation = .failed(reason) }
        if otherPending { commandOperation = .failed(reason) }
        connectionState = .connecting
        reconnectTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, !Task.isCancelled, self.wantsConnection else { return }
            self.reconnectTask = nil
            self.attemptConnect()
        }
    }

    public func disconnect() {
        suppressAutoReconnect = true
        finishSession(error: nil)
    }

    /// Starts the background Mac-link monitor. Safe to call twice: only the
    /// first call wins. The loop never opens RFCOMM by itself when the headset
    /// is off: it only joins when IOBluetooth already reports the ACL link up.
    public func startLinkMonitoring() {
        guard linkMonitorTask == nil else { return }
        linkMonitorTask = Task { @MainActor [weak self] in
            while true {
                do { try await Task.sleep(nanoseconds: 2_500_000_000) } catch { return }
                guard let self else { return }
                await self.checkMacLinkAndReconnect()
            }
        }
    }

    /// Immediate check for foreground returns and view appearances: if the Mac
    /// just connected the headset as audio, join it without waiting for the
    /// next 2,5 s poll.
    public func refreshAndReconnectIfLinked() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.checkMacLinkAndReconnect()
        }
    }

    public func noteAppBecameActive() { refreshAndReconnectIfLinked() }

    /// Error shown when no headset can be joined. Distinguishes "nothing
    /// paired" from "several XM candidates — pick one in Settings".
    private func noHeadsetError() -> String {
        if xmCandidates.count > 1 {
            return L(
                "Plusieurs casques XM sont jumelés. Choisissez le vôtre dans Réglages, puis Se connecter.",
                "Several XM headsets are paired. Pick yours in Settings, then Connect."
            )
        }
        return L(
            "Votre casque n’est pas jumelé au Mac. Vérifiez Réglages Système › Bluetooth, puis réessayez.",
            "Your headset is not paired with the Mac. Check System Settings › Bluetooth, then try again."
        )
    }

    /// Call after the interface language changes so every observing view
    /// re-renders with the other language.
    public func noteLanguageChanged() { objectWillChange.send() }

    private func candidateAddress() -> (address: String, name: String?)? {
        if let headset = personalHeadset { return (headset.id, headset.name) }
        if let address = preferences.address { return (address, preferences.name) }
        return nil
    }

    // MARK: - Personalization (open-source: user types their own names)

    /// Remembers an explicit headset choice from the picker. The address wins
    /// over auto-detection even after a rename.
    public func chooseHeadset(address: String, name: String?) {
        preferences.remember(address: address, name: name)
        objectWillChange.send()
    }

    /// Forgets the remembered headset so auto-detection runs again.
    public func forgetRememberedHeadset() {
        preferences.clearRememberedHeadset()
        objectWillChange.send()
    }

    public func setCustomDisplayName(_ value: String?) {
        preferences.setCustomDisplayName(value)
        objectWillChange.send()
    }

    public func setOwnerName(_ value: String?) {
        preferences.setOwnerName(value)
        objectWillChange.send()
    }

    public func setModelPreference(_ preference: HeadsetModelPreference) {
        preferences.setModelPreference(preference)
        objectWillChange.send()
    }

    private func checkMacLinkAndReconnect() async {
        if isBusyForAutoConnect { return }
        _ = await reloadPairedDevices()
        if isBusyForAutoConnect { return }
        guard let candidate = candidateAddress() else { return }
        let linked = connection.isLinked(toDeviceAddress: candidate.address)
        if !linked {
            // The Mac link dropped: a previous manual Déconnecter no longer
            // inhibits the next automatic join.
            if suppressAutoReconnect { suppressAutoReconnect = false }
            return
        }
        if suppressAutoReconnect { return }
        // Linked at the Mac level but no Sony session: Se connecter sans clic.
        // connect() drives device.openConnection when needed, so this also
        // covers the headset that is paired but not yet linked at the next poll.
        connect(toAddress: candidate.address, name: candidate.name)
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        let current = session
        let interval = timing.heartbeat
        heartbeatTask = Task { @MainActor [weak self] in
            while true {
                do { try await Task.sleep(nanoseconds: interval) } catch { return }
                guard let self, self.session == current, self.connectionState == .connected else { return }
                if DispatchTime.now().uptimeNanoseconds - self.lastInboundAt > self.timing.silence {
                    self.linkLost(L("Le casque ne répond plus.", "The headset stopped responding."))
                    return
                }
                // A read the headset must answer: its reply, like any frame, proves the link.
                self.commandQueue.append(.init(SonyCommands.buildBatteryGet(), group: "heartbeat"))
                self.sendNextQueuedCommand()
            }
        }
    }

    private func resetSession() {
        session = UUID()
        [ackTimeoutTask, initRetryTask, stateTimeoutTask, connectTimeoutTask, equalizerWriteTask, ambientRefreshTask, heartbeatTask, devicePollTask].forEach { $0?.cancel() }
        ackTimeoutTask = nil; initRetryTask = nil; stateTimeoutTask = nil
        connectTimeoutTask = nil; equalizerWriteTask = nil
        ambientRefreshTask = nil; heartbeatTask = nil; devicePollTask = nil; ambientSubtype = nil
        ambientReports = [:]; ambientConfirmedSubtype = nil; ambientWrittenSubtypes = []
        for change in changes.values { change.timeout?.cancel() }
        changes.removeAll()
        commandQueue.reset(); frameParser.reset()
        sequenceNumber = 0; handshakeInFlight = false; pendingProtocolVersion = nil; initRetryCount = 0
        initialStateTimedOut = false
        ambientSound = nil; battery = nil; speakToChatEnabled = nil; speakToChatConfig = nil
        automaticPowerOff = nil; pauseWhenTakenOff = nil; equalizer = nil
        listeningMode = nil; bgmRoomSize = nil; devices = nil
        bgmEnabled = nil; cinemaEnabled = nil; modeSawBGM = false; modeSawCinema = false
        modeBGMDispatched = false; modeCinemaDispatched = false
        requestedListeningMode = nil; requestedAmbientSound = nil; requestedEqualizer = nil
        requestedBGMRoomSize = nil; requestedSpeakToChatEnabled = nil; requestedSpeakToChatConfig = nil
        requestedAutomaticPowerOff = nil; requestedPauseWhenTakenOff = nil
        requestedSourceDeviceId = nil
        lastConfirmedSourceId = nil; lastSourceSwitchAt = 0
        listeningModeOperation = .idle; commandOperation = .idle; sourceOperation = .idle
        protocolVersion = .unknown
    }

    private func finishSession(error: String?) {
        let modePending = requestedListeningMode != nil
        let sourcePending = requestedSourceDeviceId != nil
        let otherPending = changes.keys.contains { $0 != Self.modeGroup && $0 != Self.sourceGroup }
        wantsConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        connection.onEvent = nil
        resetSession()
        connection.disconnect()
        connectTarget = nil
        lastError = error
        connectionState = error.map(ConnectionState.failed) ?? .disconnected
        if let error {
            if modePending { listeningModeOperation = .failed(error) }
            if sourcePending { sourceOperation = .failed(error) }
            if otherPending { commandOperation = .failed(error) }
        }
    }

    private func deadline(_ nanoseconds: UInt64, action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        let current = session
        return Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return }
            guard let self, !Task.isCancelled, self.session == current else { return }
            action()
        }
    }

    public func availability(for feature: HeadsetFeature) -> FeatureAvailability {
        let present: Bool
        switch feature {
        case .battery: present = battery != nil
        case .ambientSound: present = ambientSound != nil
        case .speakToChat: present = speakToChatEnabled != nil
        case .speakToChatConfig: present = speakToChatConfig != nil
        case .automaticPowerOff: present = automaticPowerOff != nil
        case .wearDetection: present = pauseWhenTakenOff != nil
        case .equalizer: present = equalizer != nil
        case .listeningMode: present = listeningMode != nil
        case .devices: present = devices != nil
        }
        return present ? .available : (initialStateTimedOut || connectionState != .connected ? .notReported : .loading)
    }

    public func refreshState() {
        guard connectionState == .connected else { return }
        initialStateTimedOut = false
        requestFullState()
        startStateTimeout()
    }

    private func ready() -> Bool {
        guard connectionState == .connected else {
            commandOperation = .failed(L("Connectez votre casque avant de modifier ses réglages.", "Connect your headset before changing its settings."))
            return false
        }
        return true
    }

    public func sendRaw(_ payload: [UInt8], type: SonyMessageType = .command1) {
        guard ready() else { return }
        commandQueue.append(.init(payload, type: type))
        sendNextQueuedCommand()
    }

    private func beginChange(group: String, matches: @escaping (HeadphonesEvent) -> Bool) -> UUID {
        changes[group]?.timeout?.cancel()
        let id = UUID()
        changes[group] = PendingChange(id: id, matches: matches)
        if group == Self.modeGroup { listeningModeOperation = .pending }
        else if group == Self.sourceGroup { sourceOperation = .pending }
        else { commandOperation = .pending }
        return id
    }

    private func writeBatch(group: String, id: UUID, writes: [[UInt8]], reads: [[UInt8]], type: SonyMessageType = .command1) {
        let commands = writes.map { HeadsetCommandQueue.Command($0, type: type, group: group, intent: id, isWrite: true) }
            + reads.map { HeadsetCommandQueue.Command($0, type: type, group: group, intent: id) }
        commandQueue.replace(group: group, with: commands)
        sendNextQueuedCommand()
    }

    public func setAmbientSound(_ state: AmbientSoundState) {
        guard ready() else { return }
        var value = ambientWriteValue(from: state)
        value.level = min(20, max(0, value.level))
        requestedAmbientSound = value
        ambientWrittenSubtypes = [value.subtype]
        let id = beginChange(group: "ambient", matches: Self.ambientChangeMatches(value))
        writeBatch(group: "ambient", id: id, writes: [SonyCommands.buildAmbientSoundSet(value)],
                   reads: [SonyCommands.buildAmbientSoundGet(subtype: value.subtype)])
    }

    /// Shapes a change for the dialect the device actually speaks: the subtype it
    /// reports on, and the 8-byte wind-noise form when it has ever answered that
    /// way. Echoing back whatever dialect a stale state happened to carry is how a
    /// write ends up silently ignored by the firmware.
    private func ambientWriteValue(from state: AmbientSoundState) -> AmbientSoundState {
        var value = state
        let subtype = ambientSubtype ?? value.subtype
        value.subtype = subtype
        // Mirror the shape the device last reported on this dialect; it stores the
        // body it receives, and its middle bytes hold settings we cannot read.
        if let report = ambientReports[subtype] {
            value.midBytes = report.midBytes
            value.hasWindNoiseByte = report.hasWindNoiseByte
        }
        return value
    }

    private static func ambientChangeMatches(_ value: AmbientSoundState) -> (HeadphonesEvent) -> Bool {
        { event in
            guard case .ambientSound(let reported) = event else { return false }
            return reported.mode == value.mode
                && (value.mode != .ambientSound || (reported.level == value.level && reported.focusOnVoice == value.focusOnVoice))
        }
    }

    public func setSpeakToChatEnabled(_ enabled: Bool) {
        guard ready() else { return }
        requestedSpeakToChatEnabled = enabled
        let id = beginChange(group: "speak") { if case .speakToChatEnabled(let v) = $0 { return v == enabled }; return false }
        writeBatch(group: "speak", id: id, writes: [SonyCommands.buildSpeakToChatEnabledSet(enabled)], reads: [SonyCommands.buildSpeakToChatEnabledGet()])
    }

    public func setSpeakToChatConfig(_ config: SpeakToChatConfigState) {
        guard ready() else { return }
        requestedSpeakToChatConfig = config
        let id = beginChange(group: "speakConfig") { if case .speakToChatConfig(let v) = $0 { return v == config }; return false }
        writeBatch(group: "speakConfig", id: id, writes: [SonyCommands.buildSpeakToChatConfigSet(config)], reads: [SonyCommands.buildSpeakToChatConfigGet()])
    }

    public func setAutomaticPowerOff(_ mode: AutomaticPowerOffMode) {
        guard ready() else { return }
        requestedAutomaticPowerOff = mode
        let id = beginChange(group: "power") { if case .automaticPowerOff(let v) = $0 { return v == mode }; return false }
        writeBatch(group: "power", id: id, writes: [SonyCommands.buildAutomaticPowerOffSet(mode)], reads: [SonyCommands.buildAutomaticPowerOffGet()])
    }

    public func setPauseWhenTakenOff(_ enabled: Bool) {
        guard ready() else { return }
        requestedPauseWhenTakenOff = enabled
        let id = beginChange(group: "wear") { if case .pauseWhenTakenOff(let v) = $0 { return v == enabled }; return false }
        writeBatch(group: "wear", id: id, writes: [SonyCommands.buildPauseWhenTakenOffSet(enabled)], reads: [SonyCommands.buildPauseWhenTakenOffGet()])
    }

    public func setEqualizerBands(_ bands: [Int]) {
        guard ready(), bands.count == SonyCommands.defaultBandCount else { return }
        let subtype = (requestedEqualizer ?? equalizer)?.subtype ?? 0x04
        let clamped = bands.map { min(SonyCommands.bandGainRange.upperBound, max(SonyCommands.bandGainRange.lowerBound, $0)) }
        requestedEqualizer = EqualizerState(presetCode: EqualizerPreset.custom.rawValue, bands: clamped, subtype: subtype)
        let id = beginChange(group: "equalizer") { if case .equalizer(let v) = $0 { return v.preset == .custom && v.bands == clamped }; return false }
        equalizerWriteTask?.cancel()
        // Remove already queued intermediate curves as well as debouncing the gesture.
        commandQueue.removePending(group: "equalizer")
        equalizerWriteTask = deadline(timing.equalizerDebounce) { [weak self] in
            self?.writeBatch(group: "equalizer", id: id,
                writes: [SonyCommands.buildEqualizerBandsSet(bands: clamped, subtype: subtype)],
                reads: [SonyCommands.buildEqualizerGet(subtype: subtype)])
        }
    }

    public func setEqualizerPreset(_ preset: EqualizerPreset) {
        guard ready() else { return }
        equalizerWriteTask?.cancel()
        let subtype = (requestedEqualizer ?? equalizer)?.subtype ?? 0x04
        requestedEqualizer = EqualizerState(presetCode: preset.rawValue, bands: equalizer?.bands ?? [], subtype: subtype)
        let id = beginChange(group: "equalizer") { if case .equalizer(let v) = $0 { return v.preset == preset }; return false }
        writeBatch(group: "equalizer", id: id, writes: [SonyCommands.buildEqualizerPresetSet(code: preset.rawValue, subtype: subtype)], reads: [SonyCommands.buildEqualizerGet(subtype: subtype)])
    }

    public func setListeningMode(_ mode: ListeningMode) {
        guard ready() else { return }
        if requestedListeningMode == mode { return }
        requestedListeningMode = mode
        changes.removeValue(forKey: "room")?.timeout?.cancel()
        commandQueue.removePending(group: "room")
        requestedBGMRoomSize = nil
        if commandOperation == .pending, !changes.keys.contains(where: { $0 != Self.modeGroup }) {
            commandOperation = .idle
        }
        modeBGMDispatched = false; modeCinemaDispatched = false
        modeSawBGM = false; modeSawCinema = false
        let room = requestedBGMRoomSize ?? bgmRoomSize ?? .middle
        let id = beginChange(group: Self.modeGroup) { _ in false }
        let bgm = SonyCommands.buildBGMModeSet(enabled: mode == .backgroundMusic, roomSize: room)
        let cinema = SonyCommands.buildUpmixCinemaSet(enabled: mode == .cinema)
        // Disable the mutually exclusive effect before enabling its replacement.
        let writes = mode == .backgroundMusic ? [cinema, bgm] : [bgm, cinema]
        writeBatch(group: Self.modeGroup, id: id, writes: writes,
                   reads: [SonyCommands.buildBGMModeGet(), SonyCommands.buildUpmixCinemaGet()])
    }

    public func setBGMRoomSize(_ room: BGMRoomSize) {
        guard ready(), (requestedListeningMode ?? listeningMode) == .backgroundMusic else { return }
        requestedBGMRoomSize = room
        let id = beginChange(group: "room") { if case .bgmMode(let enabled, let v) = $0 { return enabled && v == room }; return false }
        writeBatch(group: "room", id: id, writes: [SonyCommands.buildBGMModeSet(enabled: true, roomSize: room)], reads: [SonyCommands.buildBGMModeGet()])
    }

    public func refreshDevices() {
        guard connectionState == .connected else { return }
        // Ne double pas une bascule en cours : la lecture qui suit le write
        // confirme déjà la nouvelle source.
        if changes[Self.sourceGroup] != nil { return }
        if case .failed = sourceOperation { sourceOperation = .idle }
        commandQueue.append(.init(SonyCommands.buildDeviceListGet(), type: .command2, group: "read.devices"))
        sendNextQueuedCommand()
    }

    public func switchPlayback(to device: MultipointDevice) {
        guard connectionState == .connected else {
            sourceOperation = .failed(L("Connectez votre casque avant de changer de source.", "Connect your headset before switching source."))
            return
        }
        // Anti double-clic : une bascule est déjà en vol.
        guard changes[Self.sourceGroup] == nil else { return }
        guard !device.isPlayback else { return }
        guard device.isConnected else {
            sourceOperation = .failed(L("Cet appareil n’est plus connecté au casque. Reconnectez-le en Bluetooth puis actualisez la liste.", "That device is no longer connected to the headset. Reconnect it over Bluetooth, then refresh the list."))
            return
        }
        guard let payload = SonyCommands.buildSourceSwitchSet(macAddress: device.macAddress) else {
            sourceOperation = .failed(L("Adresse Bluetooth invalide pour cet appareil.", "Invalid Bluetooth address for this device."))
            return
        }
        requestedSourceDeviceId = device.id
        let id = beginChange(group: Self.sourceGroup) { if case .deviceList(let list) = $0 { return list.contains { $0.id == device.id && $0.isPlayback } }; return false }
        writeBatch(group: Self.sourceGroup, id: id, writes: [payload], reads: [SonyCommands.buildDeviceListGet()], type: .command2)
    }

    private func handle(_ event: RFCOMMConnectionEvent) {
        switch event {
        case .opened:
            guard connectionState == .connecting else { return }
            connectionState = .initializing
            sendInitAttempt()
        case .closed:
            linkLost(L("La connexion au casque a été interrompue.", "The connection to the headset was interrupted."))
        case .failed(let error): linkLost(error)
        case .dataReceived(let bytes):
            guard connectionState == .initializing || connectionState == .connected else { return }
            lastInboundAt = DispatchTime.now().uptimeNanoseconds
            protocolLog.log("RX", bytes)
            for message in frameParser.feed(bytes) {
                guard connectionState == .initializing || connectionState == .connected else { break }
                handle(message: message)
            }
        }
    }

    private func send(_ message: SonyMessage, note: String = "") {
        let bytes = message.encode()
        protocolLog.log("TX", bytes, note: note)
        connection.write(bytes)
    }

    private func sendInitAttempt() {
        handshakeInFlight = true
        send(SonyMessage(type: .command1, sequenceNumber: sequenceNumber, payload: SonyCommands.buildInit()), note: "init")
        initRetryTask?.cancel()
        initRetryTask = deadline(timing.handshake) { [weak self] in
            guard let self, self.connectionState == .initializing else { return }
            if self.initRetryCount < 2 {
                self.initRetryCount += 1
                self.sendInitAttempt()
            } else {
                self.linkLost(L("Le casque n’a pas confirmé la connexion Sony.", "The headset did not confirm the Sony connection."))
            }
        }
    }

    private func handle(message: SonyMessage) {
        if message.type == .ack {
            guard message.sequenceNumber == (sequenceNumber ^ 1), handshakeInFlight || commandQueue.inFlight != nil else { return }
            sequenceNumber = message.sequenceNumber
            if handshakeInFlight { handshakeInFlight = false; completeHandshakeIfReady(); return }
            ackTimeoutTask?.cancel()
            commandQueue.acknowledge()
            sendNextQueuedCommand()
            return
        }
        guard !message.payload.isEmpty else { return }
        send(SonyMessage(type: .ack, sequenceNumber: message.sequenceNumber ^ 1, payload: []), note: "ack")
        rawMessageHandler?(message.type, message.payload)
        guard let event = SonyEventDecoder.decode(payload: message.payload, messageType: message.type) else { return }
        apply(event)
    }

    private func apply(_ event: HeadphonesEvent) {
        switch event {
        case .protocolInfo(let version):
            guard connectionState == .initializing else { return }
            guard version != .unknown else {
                finishSession(error: L("La réponse Sony reçue n’est pas reconnue. Le casque n’a pas été mémorisé.", "The Sony reply was not recognized. The headset was not remembered."))
                return
            }
            pendingProtocolVersion = version
            completeHandshakeIfReady()
        case .ambientSound(let state):
            // Opening the app never changes ANC.
            guard acceptAmbient(state) else { return }
        // Not deduplicated on purpose: the menu bar item re-reads the system appearance
        // only when battery publishes, so a light/dark switch depends on this repeat.
        case .battery(let state): battery = state
        case .speakToChatEnabled(let state): publishIfChanged(\.speakToChatEnabled, state)
        case .speakToChatConfig(let state): publishIfChanged(\.speakToChatConfig, state)
        case .automaticPowerOff(let state): publishIfChanged(\.automaticPowerOff, state)
        case .pauseWhenTakenOff(let state): publishIfChanged(\.pauseWhenTakenOff, state)
        case .equalizer(let state): publishIfChanged(\.equalizer, state)
        case .bgmMode(let enabled, let room):
            bgmEnabled = enabled; publishIfChanged(\.bgmRoomSize, room)
            if changes[Self.modeGroup]?.started == true, modeBGMDispatched { modeSawBGM = true }
            updateListeningMode()
        case .upmixCinema(let enabled):
            cinemaEnabled = enabled
            if changes[Self.modeGroup]?.started == true, modeCinemaDispatched { modeSawCinema = true }
            updateListeningMode()
        case .deviceList(let list):
            publishIfChanged(\.devices, list)
            detectSourceSteal(list)
        }
        guard connectionState == .connected else { return }
        // Never confirm unsent changes from an older read or notification.
        let confirmed = changes.filter { $0.key != Self.modeGroup && $0.value.started && $0.value.matches(event) }.map(\.key)
        for group in confirmed {
            // A write the device echoed back and then served on a read of that
            // same dialect proves the dialect for the rest of the session.
            if group == "ambient", case .ambientSound(let reported) = event, !reported.isNotification {
                ambientConfirmedSubtype = reported.subtype
            }
            completeChange(group: group)
        }
    }

    /// A report is shown only when it comes from the dialect the device is proven
    /// to speak, because a firmware that is probed with a subtype it does not use
    /// can answer with a default (all-off) echo — and believing that echo is what
    /// makes the panel claim "Désactivé" while the headset is somewhere else.
    ///
    /// An unsolicited notification is always trusted and always re-read: it is the
    /// device talking on its own initiative (the physical button), which is the
    /// strongest evidence of both the dialect and the state. The scheduled read
    /// remains the final word, so a transitional notification can only flicker for
    /// one verify delay instead of being dropped forever.
    private func acceptAmbient(_ state: AmbientSoundState) -> Bool {
        ambientReports[state.subtype] = state
        if state.isNotification {
            ambientSubtype = state.subtype
            publishIfChanged(\.ambientSound, state)
            scheduleAmbientRefresh(after: timing.ambientVerify)
            return true
        }
        guard shouldDisplayAmbient(state.subtype) else { return false }
        ambientSubtype = state.subtype
        publishIfChanged(\.ambientSound, state)
        return true
    }

    /// A read reply can only take over a dialect the device has not confirmed with
    /// a write, and only when it is the richer form: that lets a real 0x17 report
    /// displace a 0x15 default echo, while a plain-0x15 firmware never loses its
    /// state to an echo of the wind-noise probe.
    private func shouldDisplayAmbient(_ subtype: UInt8) -> Bool {
        guard let current = ambientSubtype, current != subtype else { return true }
        if let confirmed = ambientConfirmedSubtype { return confirmed == subtype }
        return Self.ambientRank(subtype) > Self.ambientRank(current)
    }

    private static func ambientRank(_ subtype: UInt8) -> Int {
        switch subtype {
        case 0x19: return 3 // the XM6's real dialect: state reads and button notifications
        case 0x17: return 2
        case 0x15: return 1
        default: return 0
        }
    }

    private func scheduleAmbientRefresh(after nanoseconds: UInt64) {
        ambientRefreshTask?.cancel()
        ambientRefreshTask = deadline(nanoseconds) { [weak self] in self?.refreshAmbient() }
    }

    private func refreshAmbient() {
        guard connectionState == .connected else { return }
        if let subtype = ambientSubtype, changes["ambient"] == nil {
            commandQueue.append(.init(SonyCommands.buildAmbientSoundGet(subtype: subtype), group: "read.ambient"))
            sendNextQueuedCommand()
        }
        scheduleAmbientRefresh(after: timing.ambientPoll)
    }

    private func scheduleDevicePoll(after nanoseconds: UInt64) {
        devicePollTask?.cancel()
        devicePollTask = deadline(nanoseconds) { [weak self] in self?.pollDevices() }
    }

    /// Si la source active quitte l'appareil confirmé par Utiliser dans les 30 s,
    /// sans nouvelle demande, c'est l'autre appareil qui a repris la lecture.
    /// Une seule annonce, puis la liste fait foi jusqu'au prochain Utiliser.
    private func detectSourceSteal(_ list: [MultipointDevice]) {
        guard connectionState == .connected else { return }
        guard changes[Self.sourceGroup] == nil, sourceOperation == .idle else { return }
        guard let expected = lastConfirmedSourceId else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastSourceSwitchAt < Self.stealWindow else { lastConfirmedSourceId = nil; return }
        guard let active = list.first(where: { $0.isPlayback }) else { return }
        guard active.id != expected else { return }
        lastConfirmedSourceId = nil
        sourceOperation = .failed(L("« \(active.name) » a repris la lecture. Mettez-le en pause, puis touchez Utiliser à nouveau.", "“\(active.name)” resumed playback. Pause it, then tap Use again."))
    }

    /// Relit la liste multipoint tant que connecté, sans toucher à l'état
    /// d'une bascule : un vol par l'autre appareil apparaît alors seul,
    /// au pire 8 s après, au lieu d'exiger Actualiser.
    private func pollDevices() {
        guard connectionState == .connected else { return }
        if changes[Self.sourceGroup] == nil {
            commandQueue.append(.init(SonyCommands.buildDeviceListGet(), type: .command2, group: "read.devices"))
            sendNextQueuedCommand()
        }
        scheduleDevicePoll(after: timing.devicePoll)
    }

    private func completeHandshakeIfReady() {
        guard connectionState == .initializing, !handshakeInFlight,
              let version = pendingProtocolVersion else { return }
        protocolVersion = version
        initRetryTask?.cancel(); connectTimeoutTask?.cancel()
        if let target = connectTarget {
            preferences.remember(address: target.address, name: target.name)
            preferences.rememberModel(HeadsetModel.detect(fromName: target.name ?? ""))
        }
        connectionState = .connected
        reconnectAttempts = 0
        lastInboundAt = DispatchTime.now().uptimeNanoseconds
        startHeartbeat()
        requestFullState(); startStateTimeout()
        scheduleAmbientRefresh(after: timing.ambientPoll)
        scheduleDevicePoll(after: timing.devicePoll)
    }

    private func updateListeningMode() {
        guard let bgmEnabled, let cinemaEnabled else { return }
        let reported: ListeningMode = bgmEnabled ? .backgroundMusic : (cinemaEnabled ? .cinema : .standard)
        if let requestedListeningMode {
            guard modeBGMDispatched, modeCinemaDispatched, modeSawBGM, modeSawCinema, reported == requestedListeningMode,
                  bgmEnabled == (requestedListeningMode == .backgroundMusic),
                  cinemaEnabled == (requestedListeningMode == .cinema) else { return }
            publishIfChanged(\.listeningMode, reported)
            completeChange(group: Self.modeGroup)
        } else {
            publishIfChanged(\.listeningMode, reported)
        }
    }

    private func completeChange(group: String) {
        if group == Self.sourceGroup {
            // Capture la cible avant que clearRequested ne l'efface : c'est elle
            // qui sert de référence pour détecter une reprise par l'autre appareil.
            let switchedId = requestedSourceDeviceId
            changes.removeValue(forKey: group)?.timeout?.cancel()
            clearRequested(group: group)
            sourceOperation = .idle
            confirmedOperationRevision += 1
            if let switchedId {
                lastConfirmedSourceId = switchedId
                lastSourceSwitchAt = DispatchTime.now().uptimeNanoseconds
            }
            return
        }
        changes.removeValue(forKey: group)?.timeout?.cancel()
        clearRequested(group: group)
        if group == Self.modeGroup { listeningModeOperation = .idle }
        else {
            confirmedOperationRevision += 1
            if !changes.keys.contains(where: { $0 != Self.modeGroup && $0 != Self.sourceGroup }) {
                if case .failed = commandOperation {} else { commandOperation = .idle }
            }
        }
    }

    private func clearRequested(group: String) {
        switch group {
        case Self.modeGroup: requestedListeningMode = nil
        case Self.sourceGroup: requestedSourceDeviceId = nil
        case "ambient": requestedAmbientSound = nil
        case "equalizer": requestedEqualizer = nil
        case "room": requestedBGMRoomSize = nil
        case "speak": requestedSpeakToChatEnabled = nil
        case "speakConfig": requestedSpeakToChatConfig = nil
        case "power": requestedAutomaticPowerOff = nil
        case "wear": requestedPauseWhenTakenOff = nil
        default: break
        }
    }

    private func operationExpired(group: String, id: UUID) {
        guard changes[group]?.id == id else { return }
        changes.removeValue(forKey: group)?.timeout?.cancel()
        commandQueue.removePending(group: group)
        // A firmware that does not use the subtype we wrote to ignores the write
        // without a word, so a wrong dialect guess is silent. One bounded retry on
        // another dialect the device has answered is how that guess heals itself.
        if group == "ambient", let pending = requestedAmbientSound, let retry = ambientDialectRetry(from: pending) {
            requestedAmbientSound = retry
            ambientWrittenSubtypes.insert(retry.subtype)
            ambientSubtype = retry.subtype
            let retryId = beginChange(group: "ambient", matches: Self.ambientChangeMatches(retry))
            writeBatch(group: "ambient", id: retryId, writes: [SonyCommands.buildAmbientSoundSet(retry)],
                       reads: [SonyCommands.buildAmbientSoundGet(subtype: retry.subtype)])
            return
        }
        clearRequested(group: group)
        let message = L("Le casque n’a pas confirmé ce réglage. Actualisez son état ou réessayez.", "The headset did not confirm this setting. Refresh its status or try again.")
        if group == Self.modeGroup {
            listeningModeOperation = .failed(message)
            updateListeningMode()
        } else if group == Self.sourceGroup {
            sourceOperation = .failed(L("Le casque n’a pas confirmé la bascule. Si l’autre appareil joue encore (musique, vidéo, appel), mettez-le en pause puis réessayez.", "The headset did not confirm the switch. If the other device is still playing (music, video, call), pause it and try again."))
        } else {
            commandOperation = .failed(message)
        }
    }

    private func ambientDialectRetry(from request: AmbientSoundState) -> AmbientSoundState? {
        guard let subtype = Self.ambientSubtypeOrder.first(where: {
            !ambientWrittenSubtypes.contains($0) && ambientReports[$0] != nil
        }) else { return nil }
        var retry = request
        retry.subtype = subtype
        if let report = ambientReports[subtype] {
            retry.midBytes = report.midBytes
            retry.hasWindNoiseByte = report.hasWindNoiseByte
        }
        return retry
    }

    private func startStateTimeout() {
        stateTimeoutTask?.cancel()
        stateTimeoutTask = deadline(timing.initialState) { [weak self] in self?.initialStateTimedOut = true }
    }

    private func requestFullState() {
        let queries: [(String, [UInt8], SonyMessageType)] = [
            // Richest dialect first: on the XM6 only 0x19 answers with the real
            // state, and a placeholder answer must not win the first-reply race.
            ("read.ambient19", SonyCommands.buildAmbientSoundGet(subtype: 0x19), .command1),
            ("read.ambient17", SonyCommands.buildAmbientSoundGet(subtype: 0x17), .command1),
            ("read.ambient15", SonyCommands.buildAmbientSoundGet(subtype: 0x15), .command1),
            ("read.battery", SonyCommands.buildBatteryGet(), .command1),
            ("read.speak", SonyCommands.buildSpeakToChatEnabledGet(), .command1),
            ("read.speakConfig", SonyCommands.buildSpeakToChatConfigGet(), .command1),
            ("read.power", SonyCommands.buildAutomaticPowerOffGet(), .command1),
            ("read.wear", SonyCommands.buildPauseWhenTakenOffGet(), .command1),
            ("read.eq4", SonyCommands.buildEqualizerGet(subtype: 0x04), .command1),
            ("read.eq0", SonyCommands.buildEqualizerGet(subtype: 0x00), .command1),
            ("read.bgm", SonyCommands.buildBGMModeGet(), .command1),
            ("read.cinema", SonyCommands.buildUpmixCinemaGet(), .command1),
            ("read.devices", SonyCommands.buildDeviceListGet(), .command2)
        ]
        for (group, payload, type) in queries { commandQueue.append(.init(payload, type: type, group: group)) }
        sendNextQueuedCommand()
    }

    private func sendNextQueuedCommand() {
        guard connectionState == .connected, let command = commandQueue.beginNext() else { return }
        if let group = command.group, let id = command.intent, command.isWrite,
           changes[group]?.id == id, changes[group]?.started == false {
            changes[group]?.started = true
            changes[group]?.timeout = deadline(timing.operation) { [weak self] in self?.operationExpired(group: group, id: id) }
        }
        if command.group == Self.modeGroup, changes[Self.modeGroup]?.id == command.intent, command.isWrite {
            if command.payload.dropFirst().first == 0x09 { modeBGMDispatched = true; modeSawBGM = false }
            if command.payload.dropFirst().first == 0x04 { modeCinemaDispatched = true; modeSawCinema = false }
        }
        send(SonyMessage(type: command.type, sequenceNumber: sequenceNumber, payload: command.payload))
        let id = command.id
        ackTimeoutTask?.cancel()
        ackTimeoutTask = deadline(timing.acknowledgement) { [weak self] in
            guard let self, self.commandQueue.inFlight?.id == id else { return }
            // An ambiguous late ACK must never acknowledge a different command.
            // Drop this link rather than guessing Sony's retransmission policy, and
            // connect again on a clean session.
            self.linkLost(L("Le casque n’a pas accusé réception d’une commande.", "The headset did not acknowledge a command."))
        }
    }
}
