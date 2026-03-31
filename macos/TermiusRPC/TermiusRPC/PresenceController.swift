import Foundation

final class PresenceController: ObservableObject {
    @Published var status: String = "Starting..."
    @Published var isDiscordConnected: Bool = false

    private let clientID = "1417890882702540911"
    private let detector = TermiusDetector()
    private var discord: DiscordIPCClient?
    private var stateMachine = PresenceStateMachine()
    private var pollTimer: Timer?
    private var reconnectTimer: Timer?
    private let configManager: ConfigManager

    init(configManager: ConfigManager) {
        self.configManager = configManager
    }

    func start() {
        connectToDiscord()
        startPolling()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        try? discord?.clearPresence()
        discord?.disconnect()
        discord = nil
        isDiscordConnected = false
        status = "Stopped"
    }

    // MARK: - Discord Connection

    private func connectToDiscord() {
        let client = DiscordIPCClient(clientID: clientID)
        do {
            try client.connect()
            discord = client
            isDiscordConnected = true
            status = "Connected to Discord"
            reconnectTimer?.invalidate()
            reconnectTimer = nil
        } catch {
            isDiscordConnected = false
            status = "Discord not connected"
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.connectToDiscord()
        }
    }

    // MARK: - Polling

    private func startPolling() {
        poll()
        pollTimer?.invalidate()
        let interval = TimeInterval(configManager.config.clampedUpdateInterval)
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let detected = detector.detect()
        let changed = stateMachine.update(with: detected)

        updateStatus(detected)

        guard changed else { return }

        guard let discord, isDiscordConnected else {
            if detected != .closed {
                connectToDiscord()
            }
            return
        }

        do {
            switch detected {
            case .closed:
                try discord.clearPresence()
            case .idle:
                try discord.setPresence(buildIdleActivity())
            case .ssh(let host):
                try discord.setPresence(buildSSHActivity(host: host))
            case .sftp:
                try discord.setPresence(buildSFTPActivity())
            }
        } catch {
            self.discord?.disconnect()
            self.discord = nil
            isDiscordConnected = false
            status = "Discord disconnected"
            scheduleReconnect()
        }
    }

    // MARK: - Status Display

    private func updateStatus(_ state: TermiusState) {
        switch state {
        case .closed:
            status = "Termius not running"
        case .idle:
            status = "Idle in Termius"
        case .ssh(let host):
            let display = host.isEmpty ? "Active SSH session" : "SSH to \(host)"
            status = display
        case .sftp:
            status = "Browsing in SFTP"
        }
    }

    // MARK: - Activity Builders

    private func buildSSHActivity(host: String) -> DiscordActivity {
        let config = configManager.config
        let displayHost: String
        if config.privacy.showHostname && !host.isEmpty {
            displayHost = "SSH to \(host)"
        } else {
            displayHost = "Active SSH session"
        }

        return DiscordActivity(
            state: displayHost,
            details: "Connected via Termius",
            timestamps: startTimestamp(),
            assets: defaultAssets()
        )
    }

    private func buildSFTPActivity() -> DiscordActivity {
        let config = configManager.config
        let state = config.privacy.showSftpStatus ? "Browsing in SFTP" : "Idle"

        return DiscordActivity(
            state: state,
            details: "Connected via Termius",
            timestamps: startTimestamp(),
            assets: defaultAssets()
        )
    }

    private func buildIdleActivity() -> DiscordActivity {
        DiscordActivity(
            state: "Idle",
            details: "Termius",
            assets: DiscordActivity.Assets(
                largeImage: "termius",
                largeText: "Termius SSH Client"
            )
        )
    }

    private func startTimestamp() -> DiscordActivity.Timestamps? {
        guard let start = stateMachine.stateStartTime else { return nil }
        return DiscordActivity.Timestamps(start: Int(start.timeIntervalSince1970))
    }

    private func defaultAssets() -> DiscordActivity.Assets {
        DiscordActivity.Assets(
            largeImage: "termius",
            largeText: "Termius SSH Client",
            smallImage: "ssh_icon",
            smallText: "SSH"
        )
    }
}
