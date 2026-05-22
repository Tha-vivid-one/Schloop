import SwiftUI
import AppKit

@main
struct SchloopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Menu bar icon. Swaps based on app state:
/// - active     → `photo.badge.checkmark` (processing screenshots normally)
/// - paused     → `pause.circle.fill` (pause timer active)
/// - disabled   → `photo` (Quiet Mode off — "Original" tier selected)
struct MenuBarLabel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let symbol: String = {
            if appState.isPaused { return "pause.circle.fill" }
            if !appState.settings.quietMode.enabled { return "photo" }
            return "photo.badge.checkmark"
        }()
        Image(systemName: symbol)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Log.sessionStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("=== Schloop session end ===")
    }
}
