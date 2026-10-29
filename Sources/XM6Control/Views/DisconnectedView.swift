import SwiftUI
import AppKit
import SonyHeadphonesKit

/// The disconnected screen of the mockups: the headset on a cream stage, one action,
/// and the reason if the last attempt failed.
struct DisconnectedView: View {
    @EnvironmentObject private var controller: HeadphonesController

    var body: some View {
        VStack(spacing: 0) {
            stage
            Text(controller.personalHeadsetName)
                .font(MockType.largeTitle)
                .foregroundStyle(Mock.ink)
                .padding(.top, 26)
            Text("\(controller.modelLabel) · Casque déconnecté")
                .font(MockType.headingRegular)
                .foregroundStyle(Mock.ink2)
                .padding(.top, 4)
            if controller.xmCandidates.count > 1 {
                Text("Plusieurs casques XM jumelés : choisissez le vôtre dans Réglages.")
                    .font(MockType.body)
                    .foregroundStyle(Mock.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .padding(.top, 8)
            }

            Button {
                controller.autoConnect()
            } label: {
                Text(controller.personalHeadset == nil ? "Rechercher mon casque" : "Se connecter")
                    .font(MockType.heading)
                    .foregroundStyle(Mock.primaryText)
                    .padding(.horizontal, 26)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Mock.primaryFill))
                    .shadow(color: Mock.primaryShadow, radius: 8, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
            .keyboardShortcut(.defaultAction)

            if let error = controller.lastError {
                Text(error)
                    .font(MockType.body)
                    .foregroundStyle(Mock.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .padding(.top, Mock.gap)
            }
            if controller.personalHeadset == nil || controller.lastError != nil {
                Button("Ouvrir les réglages Bluetooth") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(MockType.bodyStrong)
                .foregroundStyle(Mock.accent)
                .padding(.top, Mock.gap)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Mock.emptyPaper.ignoresSafeArea())
        .task { controller.refreshAndReconnectIfLinked() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshAndReconnectIfLinked()
        }
    }

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 58, style: .continuous)
                .fill(Mock.stageFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 58, style: .continuous)
                        .strokeBorder(Mock.stageBorder, lineWidth: 0.5)
                )
                .shadow(color: Mock.stageShadow, radius: 25, y: 16)
            HeadphoneImage().padding(25)
        }
        .frame(width: 220, height: 220)
        .accessibilityHidden(true)
    }
}

/// The waiting screen of the mockups: the same stage while the headset is reached.
struct ConnectingView: View {
    @EnvironmentObject private var controller: HeadphonesController

    var body: some View {
        VStack(spacing: 0) {
            HeadphoneImage()
                .frame(width: 170, height: 170)
                .accessibilityHidden(true)
            Text(controller.deviceName ?? controller.personalHeadsetName)
                .font(MockType.largeTitle)
                .foregroundStyle(Mock.ink)
                .padding(.top, 22)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(controller.connectionState == .initializing ? "Lecture de vos réglages…" : "Connexion à votre casque…")
                    .font(MockType.headingRegular)
                    .foregroundStyle(Mock.ink2)
            }
            .padding(.top, 6)
            Button("Annuler la connexion") { controller.disconnect() }
                .buttonStyle(.plain)
                .font(MockType.bodyStrong)
                .foregroundStyle(Mock.accent)
                .padding(.top, 18)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Mock.emptyPaper.ignoresSafeArea())
    }
}
