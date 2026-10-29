import SwiftUI
import AppKit
import SonyHeadphonesKit

@main
struct XM6ControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        ProbeMode.runIfRequested()
        // Applied before any window exists, so a menu-bar-only launch never shows a
        // Dock icon. `NSApplication.shared` must exist first: `NSApp` is still nil here.
        if ProbeMode.active || AppSettings.storedMenuBarOnly {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    var body: some Scene {
        // The windows are AppKit-owned (see AppShell.swift); the only SwiftUI scene is
        // the standard Settings window and the menu commands.
        // An empty scene only: SwiftUI opens a Settings scene by itself at launch, so
        // preferences live in their own window (see PreferencesWindowController).
        Settings { EmptyView() }
        .commands {
            CommandMenu(L("Mode d’écoute", "Listening mode")) {
                Button(L("Standard", "Standard")) { AppServices.shared.controller.setListeningMode(.standard) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                    .disabled(AppServices.shared.controller.connectionState != .connected)
                Button(L("Musique de fond", "Background Music")) { AppServices.shared.controller.setListeningMode(.backgroundMusic) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                    .disabled(AppServices.shared.controller.connectionState != .connected)
                Button(L("Cinéma", "Cinema")) { AppServices.shared.controller.setListeningMode(.cinema) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                    .disabled(AppServices.shared.controller.connectionState != .connected)
            }
        }
    }
}

/// Application preferences stay separate from the headphone's own settings.
struct AppPreferencesView: View {
    @EnvironmentObject private var controller: HeadphonesController
    @EnvironmentObject private var settings: AppSettings
    @State private var displayName: String = ""
    @State private var ownerName: String = ""
    @State private var modelPreference: HeadsetModelPreference = .auto

    var body: some View {
        Form {
            Section {
                TextField(L("Nom affiché du casque", "Headset display name"), text: $displayName, prompt: Text(L("Ex. Casque de Marie, Mon XM6", "E.g. Marie's XM6, My XM6")))
                    .onAppear {
                        displayName = controller.customDisplayName ?? ""
                        ownerName = controller.ownerName ?? ""
                        modelPreference = controller.modelPreference
                    }
                    .onChange(of: displayName) { controller.setCustomDisplayName($0) }
                TextField(L("Votre prénom (optionnel)", "Your first name (optional)"), text: $ownerName, prompt: Text(L("Ex. Marie", "E.g. Marie")))
                    .onChange(of: ownerName) { controller.setOwnerName($0) }
                Picker(L("Modèle", "Model"), selection: $modelPreference) {
                    ForEach(HeadsetModelPreference.allCases) { Text($0.displayLabel).tag($0) }
                }
                .onChange(of: modelPreference) { controller.setModelPreference($0) }
                Text(L("Le nom affiché apparaît dans la fenêtre et la barre des menus. Le modèle aide à choisir quand plusieurs casques XM sont jumelés. Laissez « Automatique » dans le doute.", "The display name appears in the window and menu bar. The model helps when several XM headsets are paired. Leave Automatic when unsure."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Casque", "Headset"))
            }
            Section {
                if controller.xmCandidates.isEmpty {
                    Text(L("Aucun casque XM détecté parmi les appareils jumelés. Jumeler le casque dans Réglages Système → Bluetooth, puis revenir ici.", "No XM headset found among paired devices. Pair it in System Settings → Bluetooth, then come back."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(L("Casque suivi", "Tracked headset"), selection: headsetSelection) {
                        Text(L("Automatique", "Automatic")).tag(nil as String?)
                        ForEach(controller.xmCandidates) { device in
                            Text("\(device.name) (\(device.id))").tag(device.id as String?)
                        }
                    }
                    .onChange(of: headsetSelection.wrappedValue) { new in
                        if let id = new, let device = controller.xmCandidates.first(where: { $0.id == id }) {
                            controller.chooseHeadset(address: device.id, name: device.name)
                        } else {
                            controller.forgetRememberedHeadset()
                        }
                    }
                    if controller.personalHeadset == nil {
                        Text(L("Plusieurs casques XM correspondent : choisissez-en un ci-dessus pour ne plus avoir à le faire.", "Several XM headsets match: pick one above so you won't be asked again."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(L("Oublier le casque mémorisé", "Forget remembered headset")) { controller.forgetRememberedHeadset() }
                    .disabled(controller.personalHeadset == nil && controller.customDisplayName == nil)
            } header: {
                Text(L("Sélection", "Selection"))
            }
            Section {
                Picker(L("Langue", "Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                Toggle(L("Barre des menus uniquement", "Menu bar only"), isOn: $settings.menuBarOnly)
                Text(L("Masque l’icône du Dock et l’entrée dans le sélecteur d’apps. XM Control reste accessible depuis son icône dans la barre des menus ; la fenêtre s’ouvre depuis le panneau du casque.", "Hides the Dock icon and the app-switcher entry. XM Control stays reachable from its menu-bar icon; the window opens from the headset panel."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Application", "Application"))
            }
            Section {
                Toggle(L("Journal de diagnostic Bluetooth", "Bluetooth diagnostic log"), isOn: $controller.protocolLoggingEnabled)
                Text(L("Enregistre les échanges avec le casque pour examiner un problème. Le journal peut contenir le nom et l’adresse des appareils ; vérifiez-le avant de le partager.", "Records exchanges with the headset for troubleshooting. The log may contain device names and addresses; review it before sharing."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(L("Afficher le dossier du journal…", "Show log folder…")) {
                    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
                    let directory = base.appendingPathComponent("XM Control", isDirectory: true)
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(directory)
                }
            } header: {
                Text(L("Diagnostic", "Diagnostics"))
            }
            Section {
                LabeledContent(L("Version", "Version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("Développement", "Development"))
                Text(L("Projet indépendant, dérivé de XM6 Control par Rui Martins. Licence MIT. Aucun compte requis, aucune donnée envoyée. Photos produit Sony : voir les crédits.", "Independent project, derived from XM6 Control by Rui Martins. MIT license. No account, nothing sent anywhere. Sony product photos: see credits."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("À propos", "About"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var headsetSelection: Binding<String?> {
        Binding(
            get: {
                // The remembered address when it still matches a paired device.
                if let current = controller.personalHeadset?.id { return current }
                return nil
            },
            set: { _ in }
        )
    }
}
