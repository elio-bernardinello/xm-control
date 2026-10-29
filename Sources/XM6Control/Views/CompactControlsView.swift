import SwiftUI
import AppKit
import SonyHeadphonesKit

/// The menu bar popover, and the floating utility panel (`isDesktopWidget`). Same
/// tokens, same 16 pt rhythm and same type scale as the main window.
struct CompactControlsView: View {
    @EnvironmentObject private var controller: HeadphonesController
    /// The floating panel keeps only the frequent controls.
    var isDesktopWidget = false

    private var connected: Bool { controller.connectionState == .connected }
    private var mode: ListeningMode? { controller.requestedListeningMode ?? controller.listeningMode }
    private var ambient: AmbientSoundState? { controller.requestedAmbientSound ?? controller.ambientSound }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Mock.gap) {
                    header
                    if connected {
                        modeSection
                        noiseSection
                        equalizerRow
                        if !isDesktopWidget, let devices = controller.devices, !devices.isEmpty {
                            sourceSection(devices)
                        }
                        if let message = controller.commandFailure {
                            OperationFailureLine(message: message)
                        }
                    } else {
                        connectPrompt
                    }
                }
                .padding(Mock.gap)
            }
            .scrollIndicators(.never)
            footer
        }
        .frame(width: isDesktopWidget ? 320 : 344, height: panelHeight)
        .background(Mock.popoverPaper)
        .tint(Mock.accent)
        .task {
            controller.refreshAndReconnectIfLinked()
            controller.refreshDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshAndReconnectIfLinked()
            controller.refreshDevices()
        }
    }

    /// Sized to what the panel shows, so nothing scrolls out of sight: a base for the
    /// header and footer, one row per source, and the optional room and ambient rows.
    private var panelHeight: CGFloat {
        if isDesktopWidget { return connected ? 400 : 380 }
        guard connected else { return 380 }
        let rows = min(max(controller.devices?.count ?? 0, 1), 4)
        let room: CGFloat = mode == .backgroundMusic ? 64 : 0
        let ambientRow: CGFloat = ambient?.mode == .ambientSound ? 40 : 0
        return 340 + CGFloat(rows) * 40 + room + ambientRow
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 11) {
            MockMark(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.deviceName ?? controller.personalHeadsetName)
                    .font(MockType.heading)
                    .foregroundStyle(Mock.ink)
                    .lineLimit(1)
                Text(controller.modelLabel)
                    .font(MockType.caption)
                    .foregroundStyle(Mock.ink2)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let battery = controller.battery {
                BatteryGauge(level: battery.level, isCharging: battery.isCharging)
                    .fixedSize()
            }
            Menu {
                Button(L("Ouvrir XM Control", "Open XM Control")) { MainWindowController.shared.show() }
                if !isDesktopWidget {
                    Button(L("Ouvrir le mini-panneau", "Open the mini panel")) { MiniPanelController.shared.show() }
                }
                Button(L("Réglages de l’application…", "App settings…")) { PreferencesWindowController.shared.show() }
                Divider()
                if connected {
                    Button(L("Déconnecter le casque", "Disconnect headset")) { controller.disconnect() }
                }
                Button(L("Quitter XM Control", "Quit XM Control")) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Mock.ink2)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Mock.well))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Options", "Options"))
            .accessibilityLabel(L("Options d’XM Control", "XM Control options"))
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L("Mode d’écoute", "Listening mode"))
            TileSegment(items: ListeningMode.allCases.map {
                .init(value: $0, title: $0.displayTile, symbol: $0.symbol)
            }, selection: mode) { controller.setListeningMode($0) }
            if let message = controller.listeningModeFailure { OperationFailureLine(message: message) }
            if mode == .backgroundMusic && !isDesktopWidget {
                CompactSegment(items: BGMRoomSize.allCases.map { ($0, $0.displayLabel) },
                               selection: controller.requestedBGMRoomSize ?? controller.bgmRoomSize) {
                    controller.setBGMRoomSize($0)
                }
            }
        }
    }

    private var noiseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L("Contrôle du bruit", "Noise control"))
            CompactSegment(items: [
                (AmbientSoundMode.noiseCancelling, L("Réduction", "Noise cancelling")),
                (AmbientSoundMode.ambientSound, L("Ambiant", "Ambient")),
                (AmbientSoundMode.off, L("Désactivé", "Off")),
            ], selection: ambient?.mode) { choice in
                var updated = ambient ?? AmbientSoundState()
                updated.mode = choice
                controller.setAmbientSound(updated)
            }
            if let state = ambient, state.mode == .ambientSound {
                MockSlider(value: Double(state.level), range: 0...20) { newValue in
                    let level = Int(newValue.rounded())
                    guard level != state.level else { return }
                    var updated = state
                    updated.level = level
                    controller.setAmbientSound(updated)
                }
                .accessibilityLabel(L("Niveau du son ambiant", "Ambient sound level"))
                .padding(.top, 4)
            }
        }
    }

    private var equalizerRow: some View {
        let state = controller.requestedEqualizer ?? controller.equalizer
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Égaliseur", "Equalizer"))
                    .font(MockType.body)
                    .foregroundStyle(Mock.ink)
                Spacer()
                MockValueMenu(selection: state?.preset, options: EqualizerPreset.allCases,
                              label: { $0.displayLabel }) { controller.setEqualizerPreset($0) }
            }
            HStack(spacing: 8) {
                ForEach(CustomEqualizerCurve.allCases) { curve in
                    Button(L("EQ \(curve.rawValue)", "EQ \(curve.rawValue)")) { controller.setEqualizerBands(curve.bands) }
                        .buttonStyle(.plain)
                        .font(MockType.captionStrong)
                        .foregroundStyle(Mock.accent)
                        .help(L("\(curve.rawValue) : \(curve.detail)", "\(curve.rawValue): \(curve.detail)"))
                        .accessibilityLabel(L("Appliquer l’égaliseur \(curve.rawValue)", "Apply the \(curve.rawValue) equalizer"))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func sourceSection(_ devices: [MultipointDevice]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel(L("Source audio", "Audio source"))
            ForEach(Array(devices.prefix(4).enumerated()), id: \.element.id) { index, device in
                if index > 0 { Rectangle().fill(Mock.hair).frame(height: 0.5) }
                deviceRow(device)
            }
            if controller.isSourceSwitching {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("Basculement…", "Switching…"))
                        .font(MockType.caption)
                        .foregroundStyle(Mock.ink2)
                }
                .padding(.top, 4)
            }
            if let message = controller.sourceFailure {
                OperationFailureLine(message: message)
                    .padding(.top, 4)
            }
        }
    }

    private func deviceRow(_ device: MultipointDevice) -> some View {
        let isTarget = controller.requestedSourceDeviceId == device.id && controller.isSourceSwitching
        let switching = controller.isSourceSwitching
        let canSwitch = device.isConnected && !device.isPlayback
        return HStack(spacing: 10) {
            Image(systemName: symbolForDevice(named: device.name))
                .font(.system(size: 14))
                .foregroundStyle(device.isConnected ? Mock.ink2 : Mock.ink3)
                .frame(width: 18)
            Text(device.name)
                .font(MockType.body)
                .foregroundStyle(device.isConnected ? Mock.ink : Mock.ink3)
                .lineLimit(1)
            Spacer(minLength: 6)
            if device.isPlayback {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Mock.accent)
                    .accessibilityHidden(true)
            } else if isTarget {
                ProgressView().controlSize(.small)
            } else if canSwitch {
                Button(L("Utiliser", "Use")) { controller.switchPlayback(to: device) }
                    .buttonStyle(.plain)
                    .font(MockType.captionStrong)
                    .foregroundStyle(Mock.accent)
                    .opacity(switching ? 0.4 : 1)
                    .disabled(switching)
            } else {
                Text(switching ? L("Patientez…", "Hold on…") : L("Déconnecté", "Disconnected"))
                    .font(MockType.caption)
                    .foregroundStyle(Mock.ink3)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(device.isPlayback ? L("lecture en cours", "now playing") : (device.isConnected ? L("connecté", "connected") : L("déconnecté", "disconnected")))")
    }

    @ViewBuilder
    private var connectPrompt: some View {
        if controller.connectionState == .connecting || controller.connectionState == .initializing {
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(L("Connexion à votre casque…", "Connecting to your headset…"))
                    .font(MockType.body)
                    .foregroundStyle(Mock.ink2)
                Button(L("Annuler la connexion", "Cancel connection")) { controller.disconnect() }
                    .buttonStyle(.plain)
                    .font(MockType.bodyStrong)
                    .foregroundStyle(Mock.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            VStack(spacing: 12) {
                HeadphoneImage()
                    .frame(width: 92, height: 92)
                Text(L("Casque déconnecté", "Headset disconnected"))
                    .font(MockType.heading)
                    .foregroundStyle(Mock.ink)
                Button {
                    controller.autoConnect()
                } label: {
                    Text(controller.personalHeadset == nil ? L("Rechercher mon casque", "Find my headset") : L("Se connecter", "Connect"))
                        .font(MockType.bodyStrong)
                        .foregroundStyle(Mock.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Mock.primaryFill))
                }
                .buttonStyle(.plain)
                if let error = controller.lastError {
                    Text(error)
                        .font(MockType.caption)
                        .foregroundStyle(Mock.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Mock.hair).frame(height: 0.5)
            HStack {
                Text(isDesktopWidget ? L("Mini-panneau", "Mini panel") : L("Votre son. Votre espace.", "Your sound. Your space."))
                    .font(MockType.caption)
                    .foregroundStyle(Mock.ink3)
                Spacer()
                Button {
                    MainWindowController.shared.show()
                } label: {
                    Label(L("Ouvrir l’app", "Open the app"), systemImage: "arrow.up.right")
                        .font(MockType.bodyStrong)
                        .foregroundStyle(Mock.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Mock.gap)
            .padding(.vertical, 11)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(MockType.captionStrong)
            .foregroundStyle(Mock.ink2)
    }
}
