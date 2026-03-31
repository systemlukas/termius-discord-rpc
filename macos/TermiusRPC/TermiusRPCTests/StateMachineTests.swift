import XCTest
@testable import TermiusRPC

final class StateMachineTests: XCTestCase {
    func testInitialStateIsClosed() {
        let sm = PresenceStateMachine()
        XCTAssertEqual(sm.currentState, .closed)
    }

    func testTransitionToIdle() {
        var sm = PresenceStateMachine()
        let changed = sm.update(with: .idle)
        XCTAssertTrue(changed)
        XCTAssertEqual(sm.currentState, .idle)
    }

    func testTransitionToSSH() {
        var sm = PresenceStateMachine()
        _ = sm.update(with: .ssh(host: "homelab"))
        let changed = sm.update(with: .ssh(host: "homelab"))
        XCTAssertFalse(changed)
        XCTAssertEqual(sm.currentState, .ssh(host: "homelab"))
    }

    func testSSHDifferentHostIsChange() {
        var sm = PresenceStateMachine()
        _ = sm.update(with: .ssh(host: "homelab"))
        let changed = sm.update(with: .ssh(host: "production"))
        XCTAssertTrue(changed)
        XCTAssertEqual(sm.currentState, .ssh(host: "production"))
    }

    func testTransitionToSFTP() {
        var sm = PresenceStateMachine()
        let changed = sm.update(with: .sftp)
        XCTAssertTrue(changed)
        XCTAssertEqual(sm.currentState, .sftp)
    }

    func testTransitionToClosed() {
        var sm = PresenceStateMachine()
        _ = sm.update(with: .ssh(host: "homelab"))
        let changed = sm.update(with: .closed)
        XCTAssertTrue(changed)
        XCTAssertEqual(sm.currentState, .closed)
    }

    func testTimestampResetsOnStateChange() {
        var sm = PresenceStateMachine()
        _ = sm.update(with: .ssh(host: "homelab"))
        let ts1 = sm.stateStartTime
        XCTAssertNotNil(ts1)

        _ = sm.update(with: .ssh(host: "homelab"))
        XCTAssertEqual(sm.stateStartTime, ts1)

        Thread.sleep(forTimeInterval: 0.01)
        _ = sm.update(with: .sftp)
        XCTAssertNotEqual(sm.stateStartTime, ts1)
    }

    func testClosedClearsTimestamp() {
        var sm = PresenceStateMachine()
        _ = sm.update(with: .ssh(host: "homelab"))
        XCTAssertNotNil(sm.stateStartTime)
        _ = sm.update(with: .closed)
        XCTAssertNil(sm.stateStartTime)
    }

    func testIdleClearsTimestamp() {
        var sm = PresenceStateMachine()
        _ = sm.update(with: .ssh(host: "homelab"))
        _ = sm.update(with: .idle)
        XCTAssertNil(sm.stateStartTime)
    }
}
