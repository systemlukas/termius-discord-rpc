import Foundation

enum TitleParser {
    private static let idleKeywords: Set<String> = [
        "termius", "settings", "hosts", "host list", "groups", "snippets",
        "keychain", "port forwarding", "known hosts", "logs", "preferences",
        "account", "subscription", "appearance"
    ]

    private static let sftpKeywords: Set<String> = [
        "sftp", "files"
    ]

    private static let ipv4Pattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
    private static let ipv6Pattern = #"^[0-9a-fA-F:]+(%\w+)?$"#

    static func parse(_ title: String?) -> TermiusState {
        let raw = (title ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return .idle }

        // Extract the meaningful part before " - Termius" suffix
        let meaningful: String
        if let dashRange = raw.range(of: " - ", options: .backwards) {
            let suffix = raw[dashRange.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
            if suffix == "termius" {
                meaningful = String(raw[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            } else {
                meaningful = raw
            }
        } else {
            meaningful = raw
        }

        let lower = meaningful.lowercased()

        // Check SFTP first
        if sftpKeywords.contains(lower) {
            return .sftp
        }

        // Check idle keywords
        if idleKeywords.contains(lower) {
            return .idle
        }

        // It's an SSH session — extract and sanitize the host label
        let host = sanitizeHost(meaningful)
        return .ssh(host: host)
    }

    private static func sanitizeHost(_ raw: String) -> String {
        // If the title contains user@host, extract the host part for IP check
        let hostPart: String
        if let atIndex = raw.lastIndex(of: "@") {
            hostPart = String(raw[raw.index(after: atIndex)...])
        } else {
            hostPart = raw
        }

        // Hide raw IPs
        if isIPAddress(hostPart) {
            return ""
        }

        return raw
    }

    private static func isIPAddress(_ str: String) -> Bool {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return true
        }
        // IPv6: contains at least two colons
        if trimmed.contains(":") && trimmed.range(of: ipv6Pattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }
}
