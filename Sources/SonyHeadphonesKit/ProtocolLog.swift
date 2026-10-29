import Foundation

/// Opt-in wire diagnostics. Disabled logging performs no formatting or filesystem
/// work. Dates, file handles, directory creation and rotation all belong to one
/// utility queue, so receiving Bluetooth frames never blocks the interface.
final class ProtocolLog {
    private let enabledLock = NSLock()
    private var enabled = false
    var isEnabled: Bool {
        get {
            enabledLock.lock()
            defer { enabledLock.unlock() }
            return enabled
        }
        set {
            enabledLock.lock()
            enabled = newValue
            enabledLock.unlock()
        }
    }

    private let queue = DispatchQueue(label: "app.xmcontrol.protocol-log", qos: .utility)
    private let directory: URL?
    // Accessed only on `queue`; created lazily after logging is explicitly enabled.
    private var writer: LogWriter?

    init(directory: URL? = nil) {
        self.directory = directory
    }

    deinit {
        let finalWriter = writer
        queue.async { finalWriter?.close() }
    }

    func startSession(deviceName: String?) {
        guard isEnabled else { return }
        // Do not put a personal device name or address in the transcript.
        let timestamp = Date()
        queue.async { [self] in
            guard let writer = logWriter() else { return }
            writer.append("=== session \(writer.timestamp(timestamp)) ===\n")
        }
    }

    func log(_ direction: String, _ bytes: [UInt8], note: String = "") {
        guard isEnabled else { return }
        let timestamp = Date()
        queue.async { [self] in
            guard let writer = logWriter() else { return }
            let hex = writer.hexDump(bytes)
            let suffix = note.isEmpty ? "" : "  // " + note.replacingOccurrences(of: "\n", with: " ")
            writer.append("\(writer.timestamp(timestamp)) \(direction) \(hex)\(suffix)\n")
        }
    }

    /// Deterministic drain for diagnostics/tests; never needed for normal controls.
    func flush() {
        queue.sync { writer?.flush() }
    }

    private func logWriter() -> LogWriter? {
        if let writer { return writer }
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("XM Control", isDirectory: true)
        guard let base else { return nil }
        let newWriter = LogWriter(directory: base)
        writer = newWriter
        return newWriter
    }
}

/// All methods (including destruction through ProtocolLog) execute on its queue.
private final class LogWriter {
    private let url: URL
    private let formatter: DateFormatter
    private var handle: FileHandle?
    private var size = 0
    private let limit = 2_000_000
    private let archiveLimit = 3
    private let totalLimit = 8_000_000
    private let hexBytes = (0...255).map { String(format: "%02x", $0) }

    init(directory: URL) {
        url = directory.appendingPathComponent("protocol.log")
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pruneArchives()
    }

    func timestamp(_ date: Date) -> String { formatter.string(from: date) }
    func hexDump(_ bytes: [UInt8]) -> String { bytes.map { hexBytes[Int($0)] }.joined(separator: " ") }

    func append(_ line: String) {
        guard let rawData = line.data(using: .utf8) else { return }
        // An unexpectedly huge diagnostic entry must not bypass disk bounds.
        let data = rawData.count <= limit ? rawData : Data("Entrée de diagnostic trop volumineuse ignorée.\n".utf8)
        do {
            if handle == nil {
                if !FileManager.default.fileExists(atPath: url.path) {
                    guard FileManager.default.createFile(atPath: url.path, contents: nil) else { return }
                }
                handle = try FileHandle(forWritingTo: url)
                size = Int(try handle?.seekToEnd() ?? 0)
            }
            if size + data.count > limit {
                close()
                // Keep the three newest transcripts. Existing XM6 Control logs
                // remain in their original directory, untouched.
                let archived = url.deletingLastPathComponent()
                    .appendingPathComponent("protocol-\(UUID().uuidString).log")
                try FileManager.default.moveItem(at: url, to: archived)
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else { return }
                handle = try FileHandle(forWritingTo: url)
                size = 0
                pruneArchives()
            }
            try handle?.write(contentsOf: data)
            size += data.count
        } catch {
            // Logging must never interrupt hardware control; a future frame retries.
            close()
        }
    }

    /// Only our own archive names are eligible; no directory-wide deletion.
    /// Runs exclusively on the writer queue, including the initial cleanup of
    /// archives produced by older versions without a retention bound.
    private func pruneArchives() {
        let directory = url.deletingLastPathComponent()
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return }
        let archives = contents.compactMap { candidate -> (URL, Date, Int)? in
            guard candidate.lastPathComponent.hasPrefix("protocol-"), candidate.pathExtension == "log",
                  let values = try? candidate.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return (candidate, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        let activeSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var kept = 0
        var total = activeSize
        for (archive, _, bytes) in archives {
            if kept < archiveLimit, bytes <= limit, total + bytes <= totalLimit {
                kept += 1
                total += bytes
            } else {
                try? FileManager.default.removeItem(at: archive)
            }
        }
    }

    func flush() { try? handle?.synchronize() }
    func close() {
        try? handle?.close()
        handle = nil
    }
}
