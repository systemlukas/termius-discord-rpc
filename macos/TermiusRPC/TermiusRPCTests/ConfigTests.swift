import XCTest
@testable import TermiusRPC

final class ConfigTests: XCTestCase {
    func testDefaultConfig() {
        let config = AppConfig.default
        XCTAssertEqual(config.updateIntervalSeconds, 5)
        XCTAssertTrue(config.startOnLogin)
        XCTAssertTrue(config.privacy.showHostname)
        XCTAssertTrue(config.privacy.showSftpStatus)
    }

    func testDecodeFromJSON() throws {
        let json = """
        {
            "update_interval_seconds": 10,
            "start_on_login": false,
            "privacy": {
                "show_hostname": false,
                "show_sftp_status": true
            }
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(config.updateIntervalSeconds, 10)
        XCTAssertFalse(config.startOnLogin)
        XCTAssertFalse(config.privacy.showHostname)
        XCTAssertTrue(config.privacy.showSftpStatus)
    }

    func testEncodeToJSON() throws {
        let config = AppConfig.default
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    func testPartialJSONUsesDefaults() throws {
        let json = """
        {
            "update_interval_seconds": 3
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(config.updateIntervalSeconds, 3)
        XCTAssertTrue(config.startOnLogin)
        XCTAssertTrue(config.privacy.showHostname)
        XCTAssertTrue(config.privacy.showSftpStatus)
    }

    func testClampUpdateInterval() {
        var config = AppConfig.default
        config.updateIntervalSeconds = 0
        XCTAssertEqual(config.clampedUpdateInterval, 1)
        config.updateIntervalSeconds = 100
        XCTAssertEqual(config.clampedUpdateInterval, 60)
        config.updateIntervalSeconds = 5
        XCTAssertEqual(config.clampedUpdateInterval, 5)
    }
}
