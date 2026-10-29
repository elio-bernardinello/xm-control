import SwiftUI
import AppKit
import SonyHeadphonesKit

/// A tiny spinner in a fixed slot of the page header, so applying a setting is
/// felt without text appearing or moving the controls. Requested state is shown at
/// once; confirmation stays explicit for VoiceOver.
struct SyncIndicator: View {
    @EnvironmentObject private var controller: HeadphonesController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSyncing: Bool {
        controller.listeningModeOperation == .pending || controller.commandOperation == .pending
            || controller.sourceOperation == .pending
    }

    var body: some View {
        // Built only while syncing: a hidden spinner keeps animating and costs energy.
        // The frame is fixed, so showing it never moves the controls around it.
        ZStack {
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
        .frame(width: 16, height: 16)
        .animation(reduceMotion ? nil : Motion.hover, value: isSyncing)
        .help("Application du réglage…")
            .accessibilityHidden(true)
            .onChange(of: controller.listeningModeOperation) { operation in
                switch operation {
                case .pending: StatusAnnouncement.post("Application du mode d’écoute en cours.")
                case .failed(let message): StatusAnnouncement.post(message)
                case .idle:
                    if let mode = controller.listeningMode {
                        StatusAnnouncement.post("\(mode.frenchLabel), confirmé par le casque.")
                    }
                }
            }
            .onChange(of: controller.commandOperation) { operation in
                switch operation {
                case .pending: StatusAnnouncement.post("Application des réglages en cours.")
                case .failed(let message): StatusAnnouncement.post(message)
                case .idle: break
                }
            }
            .onChange(of: controller.sourceOperation) { operation in
                switch operation {
                case .pending: StatusAnnouncement.post("Basculement de la source audio en cours.")
                case .failed(let message): StatusAnnouncement.post(message)
                case .idle: break
                }
            }
            .onChange(of: controller.confirmedOperationRevision) { _ in
                if controller.connectionState == .connected {
                    StatusAnnouncement.post("Réglage confirmé par le casque.")
                }
            }
    }
}

/// Only a failure takes room; callers add it to the layout only when there is one.
struct OperationFailureLine: View {
    let message: String
    var font: Font = .caption

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(font)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }
}

/// Announce only operation changes, at low priority, with deduplication when the
/// window and the panel observe the same operation simultaneously.
@MainActor
private enum StatusAnnouncement {
    private static var lastMessage = ""
    private static var lastDate = Date.distantPast

    static func post(_ message: String) {
        let now = Date()
        guard message != lastMessage || now.timeIntervalSince(lastDate) > 2 else { return }
        lastMessage = message
        lastDate = now
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.low.rawValue])
    }
}
