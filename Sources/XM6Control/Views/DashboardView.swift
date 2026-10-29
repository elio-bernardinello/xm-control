import SwiftUI
import AppKit
import SonyHeadphonesKit

/// The connected window, laid out as the approved mockup: header, hero, then cards on
/// one 16 pt grid. Noise and conversation span the full width. The source and headset
/// cards share a row and stretch to the same height. The equalizer closes the page.
struct DashboardView: View {
    @EnvironmentObject private var controller: HeadphonesController
    @State private var scrollMetrics = PageScrollMetrics()

    private var mode: ListeningMode? { controller.requestedListeningMode ?? controller.listeningMode }
    private var ambient: AmbientSoundState? { controller.requestedAmbientSound ?? controller.ambientSound }

    var body: some View {
        GeometryReader { outer in
            ScrollView {
                VStack(alignment: .leading, spacing: Mock.gap) {
                    header
                    hero
                    noiseCard
                    // Two cards on one row: the grid gives both the height of the taller one.
                    Grid(alignment: .top, horizontalSpacing: Mock.gap, verticalSpacing: 0) {
                        GridRow {
                            sourceCard.frame(maxWidth: .infinity, maxHeight: .infinity)
                            headsetCard.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    conversationCard
                    equalizerCard
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 26)
                .padding(.top, 6)
                .frame(maxWidth: 840, alignment: .leading)
                .frame(maxWidth: .infinity)
                .background(PageScrollMeasure())
            }
            .coordinateSpace(name: "pageScroll")
            .scrollIndicators(.never)
            .onPreferenceChange(PageScrollMetricsKey.self) { scrollMetrics = $0 }
            .overlay(alignment: .topTrailing) {
                PageScrollThumb(metrics: scrollMetrics, viewport: outer.size.height)
            }
        }
        .background(Mock.paper.ignoresSafeArea())
        .task { controller.refreshDevices() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshDevices()
        }
    }

    // MARK: - Header and hero

    /// The page's top row. It sits under the transparent title bar, so the traffic
    /// lights and the title read as one surface. Actions are icon buttons in the
    /// same well style as the popover's options button.
    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(controller.deviceName ?? controller.personalHeadsetName)
                    .font(MockType.largeTitle)
                    .foregroundStyle(Mock.ink)
                    .lineLimit(1)
                Text(controller.modelLabel)
                    .font(MockType.caption)
                    .foregroundStyle(Mock.ink3)
                HStack(spacing: 8) {
                    Circle().fill(Mock.green).frame(width: 7, height: 7)
                    Text(statusLine)
                        .font(MockType.body)
                        .foregroundStyle(Mock.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            SyncIndicator()
                .padding(.top, 6)
            Button { controller.refreshState() } label: {
                pageIcon("arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(L("Actualiser les réglages du casque", "Refresh headset settings"))
            .accessibilityLabel(L("Actualiser les réglages du casque", "Refresh headset settings"))
            Menu {
                AppPreferencesLink()
                Divider()
                Button(L("Déconnecter le casque", "Disconnect headset"), role: .destructive) { controller.disconnect() }
            } label: {
                pageIcon("ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Options", "Options"))
            .accessibilityLabel(L("Options d’XM Control", "XM Control options"))
        }
    }

    private func pageIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Mock.ink2)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Mock.well))
            .contentShape(Circle())
    }

    private var statusLine: String {
        var parts = [L("Connecté", "Connected")]
        if let battery = controller.battery { parts.append(L("batterie \(battery.level) %", "battery \(battery.level)%")) }
        if let source = controller.devices?.first(where: { $0.isPlayback })?.name { parts.append(source) }
        return parts.joined(separator: " · ")
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 26) {
            ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(Mock.heroArtFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .strokeBorder(Mock.artBorder, lineWidth: 0.5)
                    )
                    .shadow(color: Mock.artShadow, radius: 14, y: 12)
                HeadphoneImage().padding(19)
            }
            .frame(width: 170, height: 170)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(mode?.displayLabel ?? L("Mode d’écoute", "Listening mode"))
                    .font(MockType.largeTitle)
                    .foregroundStyle(Mock.ink)
                Text(mode?.displayDetail ?? L("À vous de choisir.", "Your call."))
                    .font(MockType.headingRegular)
                    .foregroundStyle(Mock.ink2)
                    .padding(.bottom, Mock.gap)

                TileSegment(items: ListeningMode.allCases.map {
                    .init(value: $0, title: $0.tileLabel, symbol: $0.symbol)
                }, selection: mode) { controller.setListeningMode($0) }

                if let message = controller.listeningModeFailure {
                    OperationFailureLine(message: message).padding(.top, 8)
                }
                if mode == .backgroundMusic {
                    roomSelector.padding(.top, 14)
                }
                stats.padding(.top, Mock.gap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Mock.heroFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Mock.heroBorder, lineWidth: 0.5)
        )
        .shadow(color: Mock.heroShadow, radius: 14, y: 10)
    }

    private var roomSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Distance des enceintes", "Speaker distance"))
                .font(MockType.bodyStrong)
                .foregroundStyle(Mock.ink2)
            CompactSegment(items: BGMRoomSize.allCases.map { ($0, $0.displayLabel) },
                           selection: controller.requestedBGMRoomSize ?? controller.bgmRoomSize) {
                controller.setBGMRoomSize($0)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            statItem(L("Batterie", "Battery"), controller.battery.map { "\($0.level) %" } ?? "—")
            statItem(L("Bruit", "Noise"), noiseLabel)
            statItem(L("Source", "Source"), controller.devices?.first(where: { $0.isPlayback })?.name ?? "—")
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(Mock.hair).frame(height: 0.5) }
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(MockType.captionStrong)
                .tracking(0.8)
                .foregroundStyle(Mock.ink3)
            Text(value)
                .font(MockType.bodyStrong)
                .foregroundStyle(Mock.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var noiseLabel: String {
        switch ambient?.mode {
        case .noiseCancelling: return L("Réduction", "Noise cancelling")
        case .ambientSound: return L("Ambiant", "Ambient")
        case .off: return L("Désactivé", "Off")
        case nil: return "—"
        }
    }

    // MARK: - Cards

    private var noiseCard: some View {
        MockCard(title: L("Contrôle du bruit", "Noise control"), icon: "ear") {
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
                VStack(alignment: .leading, spacing: 6) {
                    MockSlider(value: Double(state.level), range: 0...20) { newValue in
                        // A drag reports many events within one level: send only real changes.
                        let level = Int(newValue.rounded())
                        guard level != state.level else { return }
                        var updated = state
                        updated.level = level
                        controller.setAmbientSound(updated)
                    }
                    .accessibilityLabel(L("Niveau du son ambiant", "Ambient sound level"))
                    HStack {
                        Text(L("Niveau ambiant", "Ambient level"))
                            .font(MockType.caption)
                            .foregroundStyle(Mock.ink3)
                        Spacer()
                        Text("\(state.level)")
                            .font(MockType.caption)
                            .monospacedDigit()
                            .foregroundStyle(Mock.ink3)
                    }
                }
                MockToggleRow(label: L("Privilégier les voix", "Prioritize voices"), isOn: state.focusOnVoice) { on in
                    var updated = state
                    updated.focusOnVoice = on
                    controller.setAmbientSound(updated)
                }
            }
        }
    }

    private var sourceCard: some View {
        MockCard(title: L("Source audio", "Audio source"), icon: "laptopcomputer.and.iphone",
                 hint: controller.devices.map { L("\($0.count) appareil\($0.count > 1 ? "s" : "")", "\($0.count) device\($0.count > 1 ? "s" : "")") }) {
            if let devices = controller.devices, !devices.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { Rectangle().fill(Mock.hair).frame(height: 0.5) }
                        sourceRow(device)
                    }
                }
                sourceFooter
            } else if controller.initialStateTimedOut {
                Text(L("Liste des appareils non communiquée par le casque.", "Device list not reported by the headset."))
                    .font(MockType.body)
                    .foregroundStyle(Mock.ink2)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        }
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if controller.isSourceSwitching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Basculement en cours…", "Switching…"))
                        .font(MockType.caption)
                        .foregroundStyle(Mock.ink2)
                }
                .padding(.top, 8)
                .accessibilityLabel(L("Basculement de la source audio en cours", "Audio source switching in progress"))
            }
            if let message = controller.sourceFailure {
                OperationFailureLine(message: message)
                    .padding(.top, 8)
                Text(L("Si l’autre appareil rejoue aussitôt, mettez-le en pause puis touchez Utiliser à nouveau.", "If the other device resumes right away, pause it, then tap Use again."))
                    .font(MockType.caption)
                    .foregroundStyle(Mock.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Actualiser la liste", "Refresh list")) { controller.refreshDevices() }
                    .buttonStyle(.plain)
                    .font(MockType.captionStrong)
                    .foregroundStyle(Mock.midnight)
                    .padding(.top, 2)
            } else if !controller.isSourceSwitching {
                Button(L("Actualiser la liste", "Refresh list")) { controller.refreshDevices() }
                    .buttonStyle(.plain)
                    .font(MockType.caption)
                    .foregroundStyle(Mock.ink3)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceRow(_ device: MultipointDevice) -> some View {
        let isTarget = controller.requestedSourceDeviceId == device.id && controller.isSourceSwitching
        let switching = controller.isSourceSwitching
        let canSwitch = device.isConnected && !device.isPlayback
        return HStack(spacing: 12) {
            Image(systemName: symbolForDevice(named: device.name))
                .font(.system(size: 17))
                .foregroundStyle(device.isConnected ? Mock.ink2 : Mock.ink3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(MockType.bodyStrong)
                    .foregroundStyle(device.isConnected ? Mock.ink : Mock.ink3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(device.isPlayback ? L("Lecture en cours", "Now playing") : (device.isConnected ? L("Connecté", "Connected") : L("Jumelé, déconnecté", "Paired, disconnected")))
                    .font(MockType.caption)
                    .foregroundStyle(Mock.ink3)
            }
            Spacer(minLength: 8)
            if device.isPlayback {
                Text(L("Actif", "Active"))
                    .font(MockType.captionStrong)
                    .foregroundStyle(Mock.midnight)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Mock.midnight.opacity(0.08)))
            } else if isTarget {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("Basculement…", "Switching…"))
                        .font(MockType.captionStrong)
                        .foregroundStyle(Mock.ink2)
                }
            } else if canSwitch {
                Button(L("Utiliser", "Use")) { controller.switchPlayback(to: device) }
                    .buttonStyle(.plain)
                    .font(MockType.captionStrong)
                    .foregroundStyle(Mock.midnight)
                    .opacity(switching ? 0.4 : 1)
                    .disabled(switching)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var headsetCard: some View {
        MockCard(title: L("Casque", "Headset"), icon: "headphones", hint: L("Détection du port", "Wear detection")) {
            if let pause = controller.requestedPauseWhenTakenOff ?? controller.pauseWhenTakenOff {
                MockToggleRow(label: L("Pause au retrait du casque", "Pause when taken off"), isOn: pause, first: true) {
                    controller.setPauseWhenTakenOff($0)
                }
            } else {
                pendingRow(L("Pause au retrait du casque", "Pause when taken off"), first: true)
            }
            if let autoOff = controller.requestedAutomaticPowerOff ?? controller.automaticPowerOff {
                MockRow(label: L("Extinction automatique", "Auto power off")) {
                    MockValueMenu(selection: autoOff, options: AutomaticPowerOffMode.allCases,
                                  label: { $0.displayLabel }) { controller.setAutomaticPowerOff($0) }
                }
            } else {
                pendingRow(L("Extinction automatique", "Auto power off"))
            }
        }
    }

    private func pendingRow(_ label: String, first: Bool = false) -> some View {
        MockRow(label: label, first: first) {
            ProgressView().controlSize(.small)
        }
    }

    private var conversationCard: some View {
        MockCard(title: L("Conversation", "Conversation"), icon: "mic", hint: "Speak-to-Chat") {
            let enabled = controller.requestedSpeakToChatEnabled ?? controller.speakToChatEnabled
            let config = controller.requestedSpeakToChatConfig ?? controller.speakToChatConfig
            if let enabled {
                MockToggleRow(label: L("Pause quand vous parlez", "Pause when you speak"), isOn: enabled, first: true) {
                    controller.setSpeakToChatEnabled($0)
                }
                if enabled, let config {
                    HStack(alignment: .top, spacing: 32) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Sensibilité", "Sensitivity"))
                                .font(MockType.caption)
                                .foregroundStyle(Mock.ink2)
                            MockValueMenu(selection: config.sensitivity, options: SpeakToChatSensitivity.allCases,
                                          label: { $0.displayLabel }) {
                                controller.setSpeakToChatConfig(SpeakToChatConfigState(sensitivity: $0, timeout: config.timeout))
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Reprendre après", "Resume after"))
                                .font(MockType.caption)
                                .foregroundStyle(Mock.ink2)
                            MockValueMenu(selection: config.timeout, options: SpeakToChatTimeout.allCases,
                                          label: { $0.displayLabel }) {
                                controller.setSpeakToChatConfig(SpeakToChatConfigState(sensitivity: config.sensitivity, timeout: $0))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                } else if enabled {
                    Text(L("Options de conversation non communiquées par le casque.", "Conversation options not reported by the headset."))
                        .font(MockType.caption)
                        .foregroundStyle(Mock.ink2)
                }
            } else if controller.initialStateTimedOut {
                StateNotReportedBanner()
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        }
    }

    private var equalizerCard: some View {
        let state = controller.requestedEqualizer ?? controller.equalizer
        let bands = state?.bands ?? []
        let custom = state?.presetCode == EqualizerPreset.custom.rawValue
        let complete = bands.count == SonyCommands.defaultBandCount
        return MockCard(title: L("Égaliseur", "Equalizer"), icon: "slider.vertical.3") {
            MockValueMenu(selection: state?.preset, options: EqualizerPreset.allCases,
                          label: { $0.displayLabel }) { controller.setEqualizerPreset($0) }
            HStack(spacing: 8) {
                ForEach(CustomEqualizerCurve.allCases) { curve in
                    Button {
                        controller.setEqualizerBands(curve.bands)
                    } label: {
                        VStack(spacing: 2) {
                            Text(curve.rawValue)
                                .font(MockType.bodyStrong)
                            Text(curve.detail)
                                .font(MockType.caption)
                                .foregroundStyle(Mock.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Mock.well))
                    }
                    .buttonStyle(.plain)
                    .help(L("Appliquer la courbe \(curve.rawValue) : \(curve.detail)", "Apply the \(curve.rawValue) curve: \(curve.detail)"))
                    .accessibilityLabel(L("Appliquer l’égaliseur \(curve.rawValue)", "Apply the \(curve.rawValue) equalizer"))
                }
            }
            .padding(.top, 8)
            ZStack(alignment: .top) {
                if complete {
                    HStack(alignment: .center, spacing: 10) {
                        ForEach(Array(bands.enumerated()), id: \.offset) { index, gain in
                            VStack(spacing: 6) {
                                EqBand(value: gain, range: SonyCommands.bandGainRange, enabled: custom) { newGain in
                                    var updated = bands
                                    updated[index] = newGain
                                    controller.setEqualizerBands(updated)
                                }
                                .frame(height: 84)
                                .accessibilityLabel(L("Bande \(Self.bandLabels.indices.contains(index) ? Self.bandLabels[index] : "\(index + 1)") hertz", "Band \(Self.bandLabels.indices.contains(index) ? Self.bandLabels[index] : "\(index + 1)") hertz"))
                                Text(Self.bandLabels.indices.contains(index) ? Self.bandLabels[index] : "")
                                    .font(MockType.caption)
                                    .foregroundStyle(Mock.ink2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    Text(custom
                         ? L("La courbe n’a pas encore été communiquée par le casque.", "The curve has not been reported by the headset yet.")
                         : L("Choisissez « Personnalisé » pour régler les bandes.", "Choose “Custom” to adjust the bands."))
                        .font(MockType.body)
                        .foregroundStyle(Mock.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 118, alignment: .top)
        }
    }

    private static let bandLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
}
