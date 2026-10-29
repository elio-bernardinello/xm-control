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
            CommandMenu("Mode d’écoute") {
                Button("Standard") { AppServices.shared.controller.setListeningMode(.standard) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                    .disabled(AppServices.shared.controller.connectionState != .connected)
                Button("Musique de fond") { AppServices.shared.controller.setListeningMode(.backgroundMusic) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                    .disabled(AppServices.shared.controller.connectionState != .connected)
                Button("Cinéma") { AppServices.shared.controller.setListeningMode(.cinema) }
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
                TextField("Nom affiché du casque", text: $displayName, prompt: Text("Ex. Casque de Marie, Mon XM6"))
                    .onAppear {
                        displayName = controller.customDisplayName ?? ""
                        ownerName = controller.ownerName ?? ""
                        modelPreference = controller.modelPreference
                    }
                    .onChange(of: displayName) { controller.setCustomDisplayName($0) }
                TextField("Votre prénom (optionnel)", text: $ownerName, prompt: Text("Ex. Marie"))
                    .onChange(of: ownerName) { controller.setOwnerName($0) }
                Picker("Modèle", selection: $modelPreference) {
                    ForEach(HeadsetModelPreference.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: modelPreference) { controller.setModelPreference($0) }
                Text("Le nom affiché apparaît dans la fenêtre et la barre des menus. Le modèle aide à choisir quand plusieurs casques XM sont jumelés. Laissez « Automatique » dans le doute.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Casque")
            }
            Section {
                if controller.xmCandidates.isEmpty {
                    Text("Aucun casque XM détecté parmi les appareils jumelés. Jumeler le casque dans Réglages Système → Bluetooth, puis revenir ici.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Casque suivi", selection: headsetSelection) {
                        Text("Automatique").tag(nil as String?)
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
                        Text("Plusieurs casques XM correspondent : choisissez-en un ci-dessus pour ne plus avoir à le faire.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Oublier le casque mémorisé") { controller.forgetRememberedHeadset() }
                    .disabled(controller.personalHeadset == nil && controller.customDisplayName == nil)
            } header: {
                Text("Sélection")
            }
            Section {
                Toggle("Barre des menus uniquement", isOn: $settings.menuBarOnly)
                Text("Masque l’icône du Dock et l’entrée dans le sélecteur d’apps. XM Control reste accessible depuis son icône dans la barre des menus ; la fenêtre s’ouvre depuis le panneau du casque.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Application")
            }
            Section {
                Toggle("Journal de diagnostic Bluetooth", isOn: $controller.protocolLoggingEnabled)
                Text("Enregistre les échanges avec le casque pour examiner un problème. Le journal peut contenir le nom et l’adresse des appareils ; vérifiez-le avant de le partager.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Afficher le dossier du journal…") {
                    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
                    let directory = base.appendingPathComponent("XM Control", isDirectory: true)
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(directory)
                }
            } header: {
                Text("Diagnostic")
            }
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Développement")
                Text("Projet indépendant, dérivé de XM6 Control par Rui Martins. Licence MIT. Aucun compte requis, aucune donnée envoyée. Les visuels Sony ne sont pas inclus.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("À propos")
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
