import Foundation
import IOBluetooth
import OSLog

public enum RFCOMMConnectionEvent: Sendable {
    case opened
    case closed
    case dataReceived([UInt8])
    case failed(String)
}

/// Injectable boundary; callers serialize commands, the implementation owns the runloop.
protocol HeadphonesTransport: AnyObject {
    var onEvent: ((RFCOMMConnectionEvent) -> Void)? { get set }
    func connect(toDeviceAddress address: String)
    func disconnect()
    func write(_ bytes: [UInt8])
    /// True when the Mac already has a Bluetooth ACL link to this address
    /// (for example the headset is connected as an audio output in
    /// Réglages Système). Used to auto-join without asking for another click.
    func isLinked(toDeviceAddress address: String) -> Bool
}

extension HeadphonesTransport {
    func isLinked(toDeviceAddress address: String) -> Bool { false }
}

public struct PairedDeviceInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
}

/// IOBluetooth remains on its original main runloop. Each connection attempt has a
/// distinct delegate, so even a late callback for the same paired device cannot
/// accidentally complete a newer connection.
public final class RFCOMMConnection: NSObject, HeadphonesTransport {
    public static let serviceUUIDv1 = "96CC203E-5068-46AD-B32D-E316F5E069BA"
    public static let serviceUUIDv2 = "956C7B26-D49A-4BA8-B03F-B17D393CB6E2"
    public var onEvent: ((RFCOMMConnectionEvent) -> Void)?

    private let generationLock = NSLock()
    private var generation: UInt64 = 0
    private var session: ConnectionSession?
    // IOBluetooth has no cancellation API for accepted device callbacks. Bound
    // quarantined delegates instead of releasing callback targets/buffers by time.
    private var retiredSessions: [ObjectIdentifier: ConnectionSession] = [:]
    private let maximumRetiredSessions = 4

    public override init() { super.init() }

    deinit {
        let lastSession = session
        DispatchQueue.main.async { lastSession?.retire() }
    }

    public static func pairedDevices() -> [PairedDeviceInfo] {
        guard let raw = IOBluetoothDevice.pairedDevices() else { return [] }
        return raw.compactMap { obj in
            guard let device = obj as? IOBluetoothDevice, let address = device.addressString else { return nil }
            return PairedDeviceInfo(id: address, name: device.name ?? device.nameOrAddress ?? address)
        }
    }

    public static func findLikelyXM() -> PairedDeviceInfo? {
        pairedDevices().first { PersonalHeadsetSelection.isXMDevice(named: $0.name) }
    }

    /// Kept for compatibility; prefer `findLikelyXM()` which covers XM4/XM5/XM6.
    public static func findLikelyXM6() -> PairedDeviceInfo? { findLikelyXM() }

    private static func device(forAddress address: String) -> IOBluetoothDevice? {
        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
           let match = paired.first(where: { $0.addressString?.caseInsensitiveCompare(address) == .orderedSame }) {
            return match
        }
        return IOBluetoothDevice(addressString: address)
    }

    private func currentGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation
    }

    private func advanceGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        generation &+= 1
        return generation
    }

    public func connect(toDeviceAddress address: String) {
        let token = advanceGeneration()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentGeneration() == token else { return }
            self.retireCurrentSession()
            guard self.retiredSessions.count < self.maximumRetiredSessions else {
                let code = self.retiredSessions.values.compactMap(\.closeFailureCode).first
                    .map { " Dernier code de fermeture : \($0)." } ?? ""
                self.onEvent?(.failed(L("macOS n’a pas terminé plusieurs opérations Bluetooth précédentes. Patientez puis réessayez ; si le problème persiste, quittez et rouvrez XM Control.", "macOS did not finish several previous Bluetooth operations. Wait and try again; if it persists, quit and reopen XM Control.") + code))
                return
            }
            guard let device = Self.device(forAddress: address) else {
                self.onEvent?(.failed(L("Casque introuvable. Vérifiez son jumelage dans les réglages Bluetooth de macOS.", "Headset not found. Check its pairing in the macOS Bluetooth settings.")))
                return
            }
            let session = ConnectionSession(device: device, emit: { [weak self] event in
                guard let self, self.currentGeneration() == token else { return }
                self.onEvent?(event)
            }, onFinished: { [weak self] finished in
                self?.retiredSessions.removeValue(forKey: ObjectIdentifier(finished))
            })
            self.session = session
            session.start()
        }
    }

    public func disconnect() {
        let token = advanceGeneration()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentGeneration() == token else { return }
            self.retireCurrentSession()
        }
    }

    private func retireCurrentSession() {
        guard let previous = session else { return }
        session = nil
        if previous.hasOutstandingWork {
            retiredSessions[ObjectIdentifier(previous)] = previous
        }
        previous.retire()
    }

    public func write(_ bytes: [UInt8]) {
        let token = currentGeneration()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentGeneration() == token else { return }
            guard let session = self.session else {
                self.onEvent?(.failed(L("Le casque n’est plus connecté. Reconnectez-le avant de réessayer.", "The headset is no longer connected. Reconnect it and try again.")))
                return
            }
            session.write(bytes)
        }
    }

    /// Synchronous link check for the auto-join monitor. Never touches the
    /// RFCOMM session: it only asks IOBluetooth whether the ACL/audio link
    /// already exists, so polling it is cheap and side-effect free.
    func isLinked(toDeviceAddress address: String) -> Bool {
        guard let device = Self.device(forAddress: address) else { return false }
        return device.isConnected()
    }
}

/// Lives until outstanding device callbacks and the channel's close callback have
/// completed. In particular, retiring a connection never releases a buffer while
/// IOBluetooth may still be using it. No timeout guesses at hardware ownership.
private final class ConnectionSession: NSObject, IOBluetoothRFCOMMChannelDelegate {
    let device: IOBluetoothDevice
    private var channel: IOBluetoothRFCOMMChannel?
    private var isRetired = false
    private var pendingDeviceCallbacks = 0
    private var lifetime: ConnectionSession?
    private var didRetryChannelOpen = false
    private var pendingWrites: [UnsafeMutableRawPointer: WriteBuffer] = [:]
    private let emit: (RFCOMMConnectionEvent) -> Void
    private let onFinished: (ConnectionSession) -> Void
    private var finishedNotified = false
    private(set) var closeFailureCode: IOReturn?
    var hasOutstandingWork: Bool { channel != nil || pendingDeviceCallbacks > 0 }
    private static let diagnostic = Logger(subsystem: "app.xmcontrol", category: "Bluetooth")

    init(device: IOBluetoothDevice, emit: @escaping (RFCOMMConnectionEvent) -> Void,
         onFinished: @escaping (ConnectionSession) -> Void) {
        self.device = device
        self.emit = emit
        self.onFinished = onFinished
        super.init()
    }

    func start() {
        lifetime = self
        if device.isConnected() { beginServiceDiscovery() }
        else {
            pendingDeviceCallbacks += 1
            let result = device.openConnection(self)
            if result != kIOReturnSuccess {
                pendingDeviceCallbacks -= 1
                fail(L("Connexion Bluetooth impossible", "Bluetooth connection impossible"), code: result)
            }
        }
    }

    func retire() {
        guard !isRetired else { releaseIfFinished(); return }
        isRetired = true
        // Keep the delegate attached until close / write-complete so submitted
        // buffers have a defined release point; retired delegates emit nothing.
        if let channel {
            let result = channel.close()
            if result != kIOReturnSuccess {
                closeFailureCode = result
                Self.diagnostic.error("Fermeture du canal Bluetooth refusée, code \(result, privacy: .public). Le délégué reste conservé pour protéger les écritures en cours.")
            }
        }
        releaseIfFinished()
    }

    private func releaseIfFinished() {
        if isRetired, !hasOutstandingWork {
            if !finishedNotified {
                finishedNotified = true
                onFinished(self)
            }
            lifetime = nil
        }
    }

    private func fail(_ message: String, code: IOReturn? = nil) {
        guard !isRetired else { return }
        let detail = code.map { " (code \($0))." } ?? "."
        emit(.failed(message + detail))
        retire()
    }

    func write(_ bytes: [UInt8]) {
        guard !isRetired, let channel, channel.isOpen() else {
            fail(L("Le canal de commande est fermé. Reconnectez le casque", "The command channel is closed. Reconnect the headset"))
            return
        }
        guard !bytes.isEmpty, bytes.count <= Int(UInt16.max), bytes.count <= Int(channel.getMTU()) else {
            fail(L("La commande dépasse la capacité du canal Bluetooth", "The command exceeds the Bluetooth channel capacity"), code: kIOReturnBadArgument)
            return
        }
        let buffer = WriteBuffer(bytes)
        let refcon = buffer.pointer
        pendingWrites[refcon] = buffer
        let result = channel.writeAsync(buffer.pointer, length: UInt16(bytes.count), refcon: refcon)
        if result != kIOReturnSuccess {
            // The SDK guarantees no data was submitted on an immediate error.
            pendingWrites.removeValue(forKey: refcon)
            fail(L("Envoi de la commande impossible", "Command could not be sent"), code: result)
        }
    }

    private func beginServiceDiscovery() {
        guard !isRetired else { return }
        if let record = serviceRecord() { openChannel(record: record); return }
        pendingDeviceCallbacks += 1
        let result = device.performSDPQuery(self)
        if result != kIOReturnSuccess {
            pendingDeviceCallbacks -= 1
            fail(L("La recherche du service Sony n’a pas pu démarrer", "The Sony service search could not start"), code: result)
        }
    }

    private func serviceRecord() -> IOBluetoothSDPServiceRecord? {
        for string in [RFCOMMConnection.serviceUUIDv2, RFCOMMConnection.serviceUUIDv1] {
            guard let uuid = UUID(uuidString: string) else { continue }
            var bytes = uuid.uuid
            let service = withUnsafeBytes(of: &bytes) { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: $0.count) }
            if let record = device.getServiceRecord(for: service) { return record }
        }
        return nil
    }

    private func openChannel(record: IOBluetoothSDPServiceRecord) {
        guard !isRetired else { return }
        var channelID: BluetoothRFCOMMChannelID = 0
        let status = record.getRFCOMMChannelID(&channelID)
        guard status == kIOReturnSuccess else {
            fail(L("Service Sony indisponible. Connectez d’abord le casque comme sortie audio", "Sony service unavailable. First connect the headset as an audio output"), code: status)
            return
        }
        var newChannel: IOBluetoothRFCOMMChannel?
        let statusOpen = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
        guard statusOpen == kIOReturnSuccess else {
            // An immediately rejected open owns no in-flight writes. Detach any
            // returned partial channel before retrying.
            newChannel?.setDelegate(nil)
            if let newChannel {
                let closeStatus = newChannel.close()
                if closeStatus != kIOReturnSuccess {
                    Self.diagnostic.error("Fermeture du canal partiel refusée, code \(closeStatus, privacy: .public).")
                }
            }
            guard !didRetryChannelOpen else {
                fail(L("Le canal de commande Sony n’a pas pu s’ouvrir", "The Sony command channel could not open"), code: statusOpen)
                return
            }
            didRetryChannelOpen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, !self.isRetired else { return }
                self.openChannel(record: record)
            }
            return
        }
        guard let newChannel else {
            fail(L("macOS n’a pas fourni de canal Bluetooth", "macOS did not provide a Bluetooth channel"), code: kIOReturnError)
            return
        }
        channel = newChannel
    }

    @objc func connectionComplete(_ callbackDevice: IOBluetoothDevice!, status: IOReturn) {
        DispatchQueue.main.async { [self] in
            guard callbackDevice === device else { return }
            pendingDeviceCallbacks = max(0, pendingDeviceCallbacks - 1)
            defer { releaseIfFinished() }
            guard !isRetired else { return }
            guard status == kIOReturnSuccess else { fail(L("Connexion au casque impossible", "Connection to the headset impossible"), code: status); return }
            beginServiceDiscovery()
        }
    }

    @objc func sdpQueryComplete(_ callbackDevice: IOBluetoothDevice!, status: IOReturn) {
        DispatchQueue.main.async { [self] in
            guard callbackDevice === device else { return }
            pendingDeviceCallbacks = max(0, pendingDeviceCallbacks - 1)
            defer { releaseIfFinished() }
            guard !isRetired else { return }
            guard status == kIOReturnSuccess else {
                fail(L("Recherche du service Sony impossible. Vérifiez la connexion audio du casque", "Sony service search failed. Check the headset audio connection"), code: status)
                return
            }
            if let record = serviceRecord() { openChannel(record: record) }
            else if (device.services as? [IOBluetoothSDPServiceRecord])?.isEmpty ?? true {
                fail(L("macOS ne signale aucun service. Autorisez XM Control dans Réglages Système → Confidentialité et sécurité → Bluetooth", "macOS reports no service. Allow XM Control in System Settings → Privacy & Security → Bluetooth"))
            } else {
                fail(L("Le service de commande Sony n’est pas disponible. Connectez le casque comme sortie audio puis réessayez", "The Sony command service is unavailable. Connect the headset as an audio output, then try again"))
            }
        }
    }

    func rfcommChannelOpenComplete(_ callbackChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        DispatchQueue.main.async { [self] in
            guard !isRetired, callbackChannel === channel else { return }
            guard error == kIOReturnSuccess else { fail(L("Ouverture du canal Sony impossible", "Sony channel opening impossible"), code: error); return }
            // Preserve the established first-write settling period, tied to this
            // exact delegate generation AND channel rather than a future session.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.isRetired, let callbackChannel,
                      callbackChannel === self.channel, callbackChannel.isOpen() else { return }
                self.emit(.opened)
            }
        }
    }

    func rfcommChannelData(_ callbackChannel: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        guard let pointer, length > 0 else { return }
        let bytes = Array(UnsafeRawBufferPointer(start: pointer, count: length))
        DispatchQueue.main.async { [self] in
            guard !isRetired, callbackChannel === channel else { return }
            emit(.dataReceived(bytes))
        }
    }

    func rfcommChannelWriteComplete(_ callbackChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        DispatchQueue.main.async { [self] in
            guard callbackChannel === channel, let refcon, pendingWrites.removeValue(forKey: refcon) != nil else { return }
            guard !isRetired else { return }
            if error != kIOReturnSuccess { fail(L("La transmission Bluetooth a échoué", "Bluetooth transmission failed"), code: error) }
        }
    }

    func rfcommChannelClosed(_ callbackChannel: IOBluetoothRFCOMMChannel!) {
        DispatchQueue.main.async { [self] in
            guard callbackChannel === channel else { return }
            callbackChannel.setDelegate(nil)
            channel = nil
            // Closed is the other terminal ownership event for all pending writes.
            pendingWrites.removeAll()
            if !isRetired { emit(.closed) }
            isRetired = true
            releaseIfFinished()
        }
    }
}

private final class WriteBuffer {
    let pointer: UnsafeMutableRawPointer
    init(_ bytes: [UInt8]) {
        pointer = .allocate(byteCount: bytes.count, alignment: MemoryLayout<UInt8>.alignment)
        bytes.withUnsafeBytes { source in pointer.copyMemory(from: source.baseAddress!, byteCount: source.count) }
    }
    deinit { pointer.deallocate() }
}
