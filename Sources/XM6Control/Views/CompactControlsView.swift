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
                Button("Ouvrir XM Control") { MainWindowController.shared.show() }
                if !isDesktopWidget {
                    Button("Ouvrir le mini-panneau") { MiniPanelController.shared.show() }
                }
                Button("Réglages de l’application…") { PreferencesWindowController.shared.show() }
                Divider()
                if connected {
                    Button("Déconnecter le casque") { controller.disconnect() }
                }
                Button("Quitter XM Control") { NSApp.terminate(nil) }
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
            .help("Options")
            .accessibilityLabel("Options d’XM Control")
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Mode d’écoute")
            TileSegment(items: ListeningMode.allCases.map {
                .init(value: $0, title: $0.tileLabel, symbol: $0.symbol)
            }, selection: mode) { controller.setListeningMode($0) }
            if let message = controller.listeningModeFailure { OperationFailureLine(message: message) }
            if mode == .backgroundMusic && !isDesktopWidget {
                CompactSegment(items: BGMRoomSize.allCases.map { ($0, $0.frenchLabel) },
                               selection: controller.requestedBGMRoomSize ?? controller.bgmRoomSize) {
                    controller.setBGMRoomSize($0)
                }
            }
        }
    }

    private var noiseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Contrôle du bruit")
            CompactSegment(items: [
                (AmbientSoundMode.noiseCancelling, "Réduction"),
                (AmbientSoundMode.ambientSound, "Ambiant"),
                (AmbientSoundMode.off, "Désactivé"),
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
                .accessibilityLabel("Niveau du son ambiant")
                .padding(.top, 4)
            }
        }
    }

    private var equalizerRow: some View {
        let state = controller.requestedEqualizer ?? controller.equalizer
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Égaliseur")
                    .font(MockType.body)
                    .foregroundStyle(Mock.ink)
                Spacer()
                MockValueMenu(selection: state?.preset, options: EqualizerPreset.allCases,
                              label: { $0.frenchLabel }) { controller.setEqualizerPreset($0) }
            }
            HStack(spacing: 8) {
                ForEach(CustomEqualizerCurve.allCases) { curve in
                    Button("EQ \(curve.rawValue)") { controller.setEqualizerBands(curve.bands) }
                        .buttonStyle(.plain)
                        .font(MockType.captionStrong)
                        .foregroundStyle(Mock.accent)
                        .help("\(curve.rawValue) : \(curve.detail)")
                        .accessibilityLabel("Appliquer l’égaliseur \(curve.rawValue)")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func sourceSection(_ devices: [MultipointDevice]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Source audio")
            ForEach(Array(devices.prefix(4).enumerated()), id: \.element.id) { index, device in
                if index > 0 { Rectangle().fill(Mock.hair).frame(height: 0.5) }
                deviceRow(device)
            }
            if controller.isSourceSwitching {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Basculement…")
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
                Button("Utiliser") { controller.switchPlayback(to: device) }
                    .buttonStyle(.plain)
                    .font(MockType.captionStrong)
                    .foregroundStyle(Mock.accent)
                    .opacity(switching ? 0.4 : 1)
                    .disabled(switching)
            } else {
                Text(switching ? "Patientez…" : "Déconnecté")
                    .font(MockType.caption)
                    .foregroundStyle(Mock.ink3)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(device.isPlayback ? "lecture en cours" : (device.isConnected ? "connecté" : "déconnecté"))")
    }

    @ViewBuilder
    private var connectPrompt: some View {
        if controller.connectionState == .connecting || controller.connectionState == .initializing {
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Connexion à votre casque…")
                    .font(MockType.body)
                    .foregroundStyle(Mock.ink2)
                Button("Annuler la connexion") { controller.disconnect() }
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
                Text("Casque déconnecté")
                    .font(MockType.heading)
                    .foregroundStyle(Mock.ink)
                Button {
                    controller.autoConnect()
                } label: {
                    Text(controller.personalHeadset == nil ? "Rechercher mon casque" : "Se connecter")
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
                Text(isDesktopWidget ? "Mini-panneau" : "Votre son. Votre espace.")
                    .font(MockType.caption)
                    .foregroundStyle(Mock.ink3)
                Spacer()
                Button {
                    MainWindowController.shared.show()
                } label: {
                    Label("Ouvrir l’app", systemImage: "arrow.up.right")
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
