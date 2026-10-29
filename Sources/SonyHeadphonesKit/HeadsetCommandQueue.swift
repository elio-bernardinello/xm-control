import Foundation

/// Serial Sony commands. The in-flight command is never discarded or superseded.
struct HeadsetCommandQueue {
    struct Command {
        let id = UUID()
        let payload: [UInt8]
        let type: SonyMessageType
        let group: String?
        let intent: UUID?
        let isWrite: Bool

        init(_ payload: [UInt8], type: SonyMessageType = .command1,
             group: String? = nil, intent: UUID? = nil, isWrite: Bool = false) {
            self.payload = payload; self.type = type; self.group = group
            self.intent = intent; self.isWrite = isWrite
        }
    }

    private(set) var pending: [Command] = []
    private(set) var inFlight: Command?

    mutating func append(_ command: Command) {
        if let group = command.group {
            pending.removeAll { $0.group == group && !$0.isWrite }
        }
        pending.append(command)
    }

    /// Replace obsolete queued values, preserving each multi-command write as a batch.
    /// Interactive changes go ahead of background reads, but not earlier user writes.
    mutating func replace(group: String, with commands: [Command]) {
        pending.removeAll { $0.group == group }
        let position = pending.firstIndex { !$0.isWrite && $0.intent == nil } ?? pending.endIndex
        pending.insert(contentsOf: commands, at: position)
    }

    mutating func beginNext() -> Command? {
        guard inFlight == nil, !pending.isEmpty else { return nil }
        let next = pending.removeFirst()
        inFlight = next
        return next
    }

    @discardableResult mutating func acknowledge() -> Command? {
        let result = inFlight
        inFlight = nil
        return result
    }

    mutating func removePending(group: String) { pending.removeAll { $0.group == group } }
    mutating func reset() { pending.removeAll(); inFlight = nil }
}
