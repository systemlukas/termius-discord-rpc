import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("General") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Start on login", isOn: Binding(
                        get: { configManager.config.startOnLogin },
                        set: { newValue in
                            configManager.updateConfig { $0.startOnLogin = newValue }
                            toggleLaunchAtLogin(enabled: newValue)
                        }
                    ))

                    HStack {
                        Text("Update interval:")
                        Stepper(
                            "\(configManager.config.clampedUpdateInterval)s",
                            value: Binding(
                                get: { configManager.config.updateIntervalSeconds },
                                set: { newValue in
                                    configManager.updateConfig { $0.updateIntervalSeconds = newValue }
                                }
                            ),
                            in: 1...60
                        )
                    }
                }
                .padding(8)
            }

            GroupBox("Privacy") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show hostname in presence", isOn: Binding(
                        get: { configManager.config.privacy.showHostname },
                        set: { newValue in
                            configManager.updateConfig { $0.privacy.showHostname = newValue }
                        }
                    ))

                    Toggle("Show SFTP status", isOn: Binding(
                        get: { configManager.config.privacy.showSftpStatus },
                        set: { newValue in
                            configManager.updateConfig { $0.privacy.showSftpStatus = newValue }
                        }
                    ))
                }
                .padding(8)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340, height: 320)
    }

    private func toggleLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            configManager.updateConfig { $0.startOnLogin = !enabled }
        }
    }
}
