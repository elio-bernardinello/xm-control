import SwiftUI
import AppKit
import SonyHeadphonesKit

/// Shown in place of a control when the headset did not report its state.
struct StateNotReportedBanner: View {
    var body: some View {
        Label("État non communiqué par le casque. Les réglages restent disponibles.", systemImage: "info.circle")
            .font(MockType.caption)
            .foregroundStyle(Mock.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Opens the application's own preferences window.
struct AppPreferencesLink: View {
    var body: some View {
        Button("Réglages de l’application…") { PreferencesWindowController.shared.show() }
    }
}

extension HeadphonesController {
    var listeningModeFailure: String? {
        if case .failed(let message) = listeningModeOperation { return message }
        return nil
    }
    var commandFailure: String? {
        if case .failed(let message) = commandOperation { return message }
        return nil
    }
    var sourceFailure: String? {
        if case .failed(let message) = sourceOperation { return message }
        return nil
    }
    var isSourceSwitching: Bool {
        sourceOperation == .pending
    }
}
