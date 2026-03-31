import Foundation

struct PrivacyConfig: Codable, Equatable {
    var showHostname: Bool
    var showSftpStatus: Bool

    enum CodingKeys: String, CodingKey {
        case showHostname = "show_hostname"
        case showSftpStatus = "show_sftp_status"
    }

    init(showHostname: Bool = true, showSftpStatus: Bool = true) {
        self.showHostname = showHostname
        self.showSftpStatus = showSftpStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showHostname = try container.decodeIfPresent(Bool.self, forKey: .showHostname) ?? true
        showSftpStatus = try container.decodeIfPresent(Bool.self, forKey: .showSftpStatus) ?? true
    }
}

struct AppConfig: Codable, Equatable {
    var updateIntervalSeconds: Int
    var startOnLogin: Bool
    var privacy: PrivacyConfig

    enum CodingKeys: String, CodingKey {
        case updateIntervalSeconds = "update_interval_seconds"
        case startOnLogin = "start_on_login"
        case privacy
    }

    init(
        updateIntervalSeconds: Int = 5,
        startOnLogin: Bool = true,
        privacy: PrivacyConfig = PrivacyConfig()
    ) {
        self.updateIntervalSeconds = updateIntervalSeconds
        self.startOnLogin = startOnLogin
        self.privacy = privacy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updateIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .updateIntervalSeconds) ?? 5
        startOnLogin = try container.decodeIfPresent(Bool.self, forKey: .startOnLogin) ?? true
        privacy = try container.decodeIfPresent(PrivacyConfig.self, forKey: .privacy) ?? PrivacyConfig()
    }

    static let `default` = AppConfig()

    var clampedUpdateInterval: Int {
        min(max(updateIntervalSeconds, 1), 60)
    }
}

final class ConfigManager: ObservableObject {
    @Published var config: AppConfig

    private let configURL: URL
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("TermiusRPC")

        configURL = appSupport.appendingPathComponent("config.json")
        config = AppConfig.default

        ensureConfigDirectory(appSupport)
        config = loadConfig()
        startWatching()
    }

    private func ensureConfigDirectory(_ dir: URL) {
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: configURL.path) {
            saveConfig(AppConfig.default)
        }
    }

    func loadConfig() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig.default
        }
        return decoded
    }

    func saveConfig(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    func updateConfig(_ transform: (inout AppConfig) -> Void) {
        var updated = config
        transform(&updated)
        config = updated
        saveConfig(updated)
    }

    private func startWatching() {
        fileDescriptor = open(configURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.restartWatching()
            }
            self.config = self.loadConfig()
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        source.resume()
        dispatchSource = source
    }

    private func restartWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startWatching()
        }
    }

    deinit {
        dispatchSource?.cancel()
    }
}
