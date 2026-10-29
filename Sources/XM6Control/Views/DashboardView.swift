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
            .help("Actualiser les réglages du casque")
            .accessibilityLabel("Actualiser les réglages du casque")
            Menu {
                AppPreferencesLink()
                Divider()
                Button("Déconnecter le casque", role: .destructive) { controller.disconnect() }
            } label: {
                pageIcon("ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Options")
            .accessibilityLabel("Options d’XM Control")
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
        var parts = ["Connecté"]
        if let battery = controller.battery { parts.append("batterie \(battery.level) %") }
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
                Text(mode?.frenchLabel ?? "Mode d’écoute")
                    .font(MockType.largeTitle)
                    .foregroundStyle(Mock.ink)
                Text(mode?.detail ?? "À vous de choisir.")
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
            Text("Distance des enceintes")
                .font(MockType.bodyStrong)
                .foregroundStyle(Mock.ink2)
            CompactSegment(items: BGMRoomSize.allCases.map { ($0, $0.frenchLabel) },
                           selection: controller.requestedBGMRoomSize ?? controller.bgmRoomSize) {
                controller.setBGMRoomSize($0)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            statItem("Batterie", controller.battery.map { "\($0.level) %" } ?? "—")
            statItem("Bruit", noiseLabel)
            statItem("Source", controller.devices?.first(where: { $0.isPlayback })?.name ?? "—")
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
        case .noiseCancelling: return "Réduction"
        case .ambientSound: return "Ambiant"
        case .off: return "Désactivé"
        case nil: return "—"
        }
    }

    // MARK: - Cards

    private var noiseCard: some View {
        MockCard(title: "Contrôle du bruit", icon: "ear") {
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
                VStack(alignment: .leading, spacing: 6) {
                    MockSlider(value: Double(state.level), range: 0...20) { newValue in
                        // A drag reports many events within one level: send only real changes.
                        let level = Int(newValue.rounded())
                        guard level != state.level else { return }
                        var updated = state
                        updated.level = level
                        controller.setAmbientSound(updated)
                    }
                    .accessibilityLabel("Niveau du son ambiant")
                    HStack {
                        Text("Niveau ambiant")
                            .font(MockType.caption)
                            .foregroundStyle(Mock.ink3)
                        Spacer()
                        Text("\(state.level)")
                            .font(MockType.caption)
                            .monospacedDigit()
                            .foregroundStyle(Mock.ink3)
                    }
                }
                MockToggleRow(label: "Privilégier les voix", isOn: state.focusOnVoice) { on in
                    var updated = state
                    updated.focusOnVoice = on
                    controller.setAmbientSound(updated)
                }
            }
        }
    }

    private var sourceCard: some View {
        MockCard(title: "Source audio", icon: "laptopcomputer.and.iphone",
                 hint: controller.devices.map { "\($0.count) appareil\($0.count > 1 ? "s" : "")" }) {
            if let devices = controller.devices, !devices.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { Rectangle().fill(Mock.hair).frame(height: 0.5) }
                        sourceRow(device)
                    }
                }
                sourceFooter
            } else if controller.initialStateTimedOut {
                Text("Liste des appareils non communiquée par le casque.")
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
                    Text("Basculement en cours…")
                        .font(MockType.caption)
                        .foregroundStyle(Mock.ink2)
                }
                .padding(.top, 8)
                .accessibilityLabel("Basculement de la source audio en cours")
            }
            if let message = controller.sourceFailure {
                OperationFailureLine(message: message)
                    .padding(.top, 8)
                Text("Si l’iPhone rejoue aussitôt, mettez-le en pause puis touchez Utiliser à nouveau.")
                    .font(MockType.caption)
                    .foregroundStyle(Mock.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Actualiser la liste") { controller.refreshDevices() }
                    .buttonStyle(.plain)
                    .font(MockType.captionStrong)
                    .foregroundStyle(Mock.midnight)
                    .padding(.top, 2)
            } else if !controller.isSourceSwitching {
                Button("Actualiser la liste") { controller.refreshDevices() }
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
                Text(device.isPlayback ? "Lecture en cours" : (device.isConnected ? "Connecté" : "Jumelé, déconnecté"))
                    .font(MockType.caption)
                    .foregroundStyle(Mock.ink3)
            }
            Spacer(minLength: 8)
            if device.isPlayback {
                Text("Actif")
                    .font(MockType.captionStrong)
                    .foregroundStyle(Mock.midnight)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Mock.midnight.opacity(0.08)))
            } else if isTarget {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Basculement…")
                        .font(MockType.captionStrong)
                        .foregroundStyle(Mock.ink2)
                }
            } else if canSwitch {
                Button("Utiliser") { controller.switchPlayback(to: device) }
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
        MockCard(title: "Casque", icon: "headphones", hint: "Détection du port") {
            if let pause = controller.requestedPauseWhenTakenOff ?? controller.pauseWhenTakenOff {
                MockToggleRow(label: "Pause au retrait du casque", isOn: pause, first: true) {
                    controller.setPauseWhenTakenOff($0)
                }
            } else {
                pendingRow("Pause au retrait du casque", first: true)
            }
            if let autoOff = controller.requestedAutomaticPowerOff ?? controller.automaticPowerOff {
                MockRow(label: "Extinction automatique") {
                    MockValueMenu(selection: autoOff, options: AutomaticPowerOffMode.allCases,
                                  label: { $0.frenchLabel }) { controller.setAutomaticPowerOff($0) }
                }
            } else {
                pendingRow("Extinction automatique")
            }
        }
    }

    private func pendingRow(_ label: String, first: Bool = false) -> some View {
        MockRow(label: label, first: first) {
            ProgressView().controlSize(.small)
        }
    }

    private var conversationCard: some View {
        MockCard(title: "Conversation", icon: "mic", hint: "Speak-to-Chat") {
            let enabled = controller.requestedSpeakToChatEnabled ?? controller.speakToChatEnabled
            let config = controller.requestedSpeakToChatConfig ?? controller.speakToChatConfig
            if let enabled {
                MockToggleRow(label: "Pause quand vous parlez", isOn: enabled, first: true) {
                    controller.setSpeakToChatEnabled($0)
                }
                if enabled, let config {
                    HStack(alignment: .top, spacing: 32) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sensibilité")
                                .font(MockType.caption)
                                .foregroundStyle(Mock.ink2)
                            MockValueMenu(selection: config.sensitivity, options: SpeakToChatSensitivity.allCases,
                                          label: { $0.frenchLabel }) {
                                controller.setSpeakToChatConfig(SpeakToChatConfigState(sensitivity: $0, timeout: config.timeout))
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reprendre après")
                                .font(MockType.caption)
                                .foregroundStyle(Mock.ink2)
                            MockValueMenu(selection: config.timeout, options: SpeakToChatTimeout.allCases,
                                          label: { $0.frenchLabel }) {
                                controller.setSpeakToChatConfig(SpeakToChatConfigState(sensitivity: config.sensitivity, timeout: $0))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                } else if enabled {
                    Text("Options de conversation non communiquées par le casque.")
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
        return MockCard(title: "Égaliseur", icon: "slider.vertical.3") {
            MockValueMenu(selection: state?.preset, options: EqualizerPreset.allCases,
                          label: { $0.frenchLabel }) { controller.setEqualizerPreset($0) }
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
                    .help("Appliquer la courbe \(curve.rawValue) : \(curve.detail)")
                    .accessibilityLabel("Appliquer l’égaliseur \(curve.rawValue)")
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
                                .accessibilityLabel("Bande \(Self.bandLabels.indices.contains(index) ? Self.bandLabels[index] : "\(index + 1)") hertz")
                                Text(Self.bandLabels.indices.contains(index) ? Self.bandLabels[index] : "")
                                    .font(MockType.caption)
                                    .foregroundStyle(Mock.ink2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    Text(custom
                         ? "La courbe n’a pas encore été communiquée par le casque."
                         : "Choisissez « Personnalisé » pour régler les bandes.")
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
