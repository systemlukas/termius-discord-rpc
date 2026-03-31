import Foundation

enum TermiusState: Equatable {
    case closed
    case idle
    case ssh(host: String)
    case sftp
}

struct PresenceStateMachine {
    private(set) var currentState: TermiusState = .closed
    private(set) var stateStartTime: Date?

    /// Update the state. Returns true if the state changed.
    mutating func update(with newState: TermiusState) -> Bool {
        guard newState != currentState else { return false }
        currentState = newState

        switch newState {
        case .closed, .idle:
            stateStartTime = nil
        case .ssh, .sftp:
            stateStartTime = Date()
        }

        return true
    }
}
