import SwiftUI
import AppKit
import Combine
import SonyHeadphonesKit

/// The single controller and settings store, shared by every window and the menu bar.
@MainActor
final class AppServices {
    static let shared = AppServices()
    let controller = HeadphonesController()
    let settings = AppSettings()

    private init() {}
}

/// Owns the AppKit shell. The status item, the main window and the utility panel are
/// plain AppKit windows, so macOS draws their shape, shadow and material itself. The
/// SwiftUI views are only their contents.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProbeMode.active { return }
        // Repeats the policy chosen in `init`, which SwiftUI can reset while it builds scenes.
        AppServices.shared.settings.apply()
        statusItem = StatusItemController()
        // Closes a preferences window SwiftUI may open on its own at launch.
        NSApp.windows.filter { $0.title.hasPrefix(L("Réglages", "Settings")) }.forEach { $0.orderOut(nil) }
        if !AppSettings.storedMenuBarOnly {
            MainWindowController.shared.show()
        }
        AppServices.shared.controller.autoConnect()
        AppServices.shared.controller.startLinkMonitoring()
    }

    /// Clicking the Dock icon with no window open brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowController.shared.show() }
        return true
    }
}

/// The menu bar item: the battery badge, and a popover with the controls.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private let controller = AppServices.shared.controller

    override init() {
        super.init()
        let root = CompactControlsView()
            .environmentObject(controller)
            .environmentObject(AppServices.shared.settings)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: root)

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        Publishers.CombineLatest(controller.$connectionState, controller.$battery)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refresh() }
            .store(in: &cancellables)
        // The glyph is menu-bar ink, black or white: it must be redrawn when the
        // system switches appearance, not only when the battery changes.
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    private var badgeState: MenuBarBadge.State {
        switch controller.connectionState {
        case .connected:
            return .connected(level: controller.battery?.level, charging: controller.battery?.isCharging ?? false)
        case .connecting, .initializing:
            return .connecting
        default:
            return .disconnected
        }
    }

    private func refresh() {
        guard let button = item.button else { return }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        button.image = MenuBarBadge.image(for: badgeState, darkMenuBar: dark)
        button.setAccessibilityLabel(spokenState)
    }

    private var spokenState: String {
        guard case .connected(let level, let charging) = badgeState else { return L("XM Control, casque non connecté", "XM Control, headset not connected") }
        guard let level else { return L("XM Control, connecté", "XM Control, connected") }
        return L("XM Control, batterie à \(level) pour cent\(charging ? ", en charge" : "")", "XM Control, battery at \(level) percent\(charging ? ", charging" : "")")
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// The main window: created on demand and kept, so closing it hides it and reopening
/// it restores the same window at the same place.
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()
    private var window: NSWindow?

    /// The window's own colour, behind the SwiftUI page and during live resizing.
    private static let paperColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0x17 / 255, green: 0x14 / 255, blue: 0x10 / 255, alpha: 1)
        }
        return NSColor(srgbRed: 0xF6 / 255, green: 0xF3 / 255, blue: 0xEC / 255, alpha: 1)
    }

    func show() {
        if window == nil {
            let root = ContentView()
                .environmentObject(AppServices.shared.controller)
                .environmentObject(AppServices.shared.settings)
                .frame(minWidth: 620, minHeight: 520)
            let hosting = NSHostingController(rootView: root)
            let created = NSWindow(contentViewController: hosting)
            created.title = "XM Control"
            created.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            // The title bar belongs to the cream page: content runs under a transparent
            // bar, so there is no grey band and no separate toolbar. Actions live in the page.
            created.titlebarAppearsTransparent = true
            created.titleVisibility = .hidden
            created.isMovableByWindowBackground = true
            created.isReleasedWhenClosed = false
            created.setContentSize(NSSize(width: 880, height: 820))
            created.backgroundColor = Self.paperColor
            created.setFrameAutosaveName("main")
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The floating utility panel: a standard titled utility window that stays above
/// other windows. Native chrome, native shadow, no custom shape to get wrong.
@MainActor
final class MiniPanelController {
    static let shared = MiniPanelController()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let root = CompactControlsView(isDesktopWidget: true)
                .environmentObject(AppServices.shared.controller)
                .environmentObject(AppServices.shared.settings)
            let created = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 470),
                                  styleMask: [.titled, .closable, .utilityWindow],
                                  backing: .buffered, defer: false)
            created.title = "Mini-panneau"
            created.isFloatingPanel = true
            created.level = .floating
            created.hidesOnDeactivate = false
            created.isReleasedWhenClosed = false
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.contentViewController = NSHostingController(rootView: root)
            created.setFrameAutosaveName("XMControlMiniPanel")
            created.center()
            panel = created
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}

/// Preferences window, opened only on request.
@MainActor
final class PreferencesWindowController {
    static let shared = PreferencesWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let root = AppPreferencesView()
                .environmentObject(AppServices.shared.controller)
                .environmentObject(AppServices.shared.settings)
            let created = NSWindow(contentViewController: NSHostingController(rootView: root))
            created.title = L("Réglages XM Control", "XM Control Settings")
            created.styleMask.insert([.titled, .closable])
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
