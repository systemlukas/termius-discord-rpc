import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var presenceController: PresenceController
    @EnvironmentObject var configManager: ConfigManager
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(presenceController.status)
                    .font(.system(.body, design: .monospaced))
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: presenceController.isDiscordConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(presenceController.isDiscordConnected ? .green : .red)
                Text(presenceController.isDiscordConnected ? "Discord connected" : "Discord not connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button("Settings...") {
                showSettings = true
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(configManager)
            }

            Button("Quit") {
                presenceController.stop()
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260)
    }

    private var statusColor: Color {
        if presenceController.status.contains("SSH") || presenceController.status.contains("SFTP") {
            return .green
        } else if presenceController.status.contains("Idle") {
            return .yellow
        } else if presenceController.status.contains("not running") {
            return .gray
        } else {
            return .orange
        }
    }
}
