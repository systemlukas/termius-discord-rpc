import XCTest
@testable import TermiusRPC

final class TitleParserTests: XCTestCase {
    // MARK: - SSH detection

    func testSSHWithUserAtHost() {
        let state = TitleParser.parse("root@homelab")
        XCTAssertEqual(state, .ssh(host: "root@homelab"))
    }

    func testSSHWithHostOnly() {
        let state = TitleParser.parse("my-server")
        XCTAssertEqual(state, .ssh(host: "my-server"))
    }

    func testSSHWithHostAndSuffix() {
        let state = TitleParser.parse("homelab - Termius")
        XCTAssertEqual(state, .ssh(host: "homelab"))
    }

    func testSSHWithUserAtHostAndSuffix() {
        let state = TitleParser.parse("root@prod - Termius")
        XCTAssertEqual(state, .ssh(host: "root@prod"))
    }

    // MARK: - IP privacy

    func testIPv4IsHidden() {
        let state = TitleParser.parse("192.168.1.100")
        XCTAssertEqual(state, .ssh(host: ""))
    }

    func testIPv4WithUserIsHidden() {
        let state = TitleParser.parse("root@192.168.1.100")
        XCTAssertEqual(state, .ssh(host: ""))
    }

    func testIPv6IsHidden() {
        let state = TitleParser.parse("::1")
        XCTAssertEqual(state, .ssh(host: ""))
    }

    func testIPv6FullIsHidden() {
        let state = TitleParser.parse("fe80::1%en0")
        XCTAssertEqual(state, .ssh(host: ""))
    }

    // MARK: - SFTP detection

    func testSFTPInTitle() {
        let state = TitleParser.parse("SFTP - Termius")
        XCTAssertEqual(state, .sftp)
    }

    func testSFTPLowercase() {
        let state = TitleParser.parse("sftp")
        XCTAssertEqual(state, .sftp)
    }

    func testFilesInTitle() {
        let state = TitleParser.parse("Files - Termius")
        XCTAssertEqual(state, .sftp)
    }

    // MARK: - Idle / generic views

    func testTermiusOnly() {
        let state = TitleParser.parse("Termius")
        XCTAssertEqual(state, .idle)
    }

    func testSettingsIsIdle() {
        let state = TitleParser.parse("Settings - Termius")
        XCTAssertEqual(state, .idle)
    }

    func testHostsIsIdle() {
        let state = TitleParser.parse("Hosts - Termius")
        XCTAssertEqual(state, .idle)
    }

    func testSnippetsIsIdle() {
        let state = TitleParser.parse("Snippets - Termius")
        XCTAssertEqual(state, .idle)
    }

    func testKeychainIsIdle() {
        let state = TitleParser.parse("Keychain - Termius")
        XCTAssertEqual(state, .idle)
    }

    func testEmptyIsIdle() {
        let state = TitleParser.parse("")
        XCTAssertEqual(state, .idle)
    }

    func testNilIsIdle() {
        let state = TitleParser.parse(nil)
        XCTAssertEqual(state, .idle)
    }
}
