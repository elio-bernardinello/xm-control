import SwiftUI
import AppKit
import SonyHeadphonesKit

/// The main window's content: one of three screens, chosen by the connection.
/// Connecting is started by the app delegate at launch, not by the view, so reopening
/// the window never tears down a live session.
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var controller: HeadphonesController

    var body: some View {
        Group {
            switch controller.connectionState {
            case .disconnected, .failed, .searching:
                DisconnectedView()
            case .connecting, .initializing:
                ConnectingView()
            case .connected:
                DashboardView()
            }
        }
        .id(scenePhase)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
        .animation(reduceMotion ? nil : Motion.sceneChange, value: scenePhase)
    }

    /// Collapses the connection states into the three things the UI actually shows,
    /// so moving between, say, connecting and initializing doesn't re-run the
    /// transition on a view that hasn't changed.
    private var scenePhase: Int {
        switch controller.connectionState {
        case .disconnected, .failed, .searching: return 0
        case .connecting, .initializing: return 1
        case .connected: return 2
        }
    }
}
