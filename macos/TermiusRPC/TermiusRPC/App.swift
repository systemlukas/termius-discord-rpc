import SwiftUI

@main
struct TermiusRPCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState.presenceController)
                .environmentObject(appState.configManager)
        } label: {
            Image(systemName: "terminal")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppState: ObservableObject {
    let configManager: ConfigManager
    let presenceController: PresenceController

    init() {
        let cm = ConfigManager()
        configManager = cm
        presenceController = PresenceController(configManager: cm)
        presenceController.start()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
