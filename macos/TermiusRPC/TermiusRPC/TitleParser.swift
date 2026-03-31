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

        // Extract meaningful part from window title.
        // Termius uses both formats:
        //   "Termius - <view>"  (prefix, macOS confirmed)
        //   "<view> - Termius"  (suffix, Windows)
        let meaningful = extractMeaningfulPart(raw)
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

    private static func extractMeaningfulPart(_ raw: String) -> String {
        // Try "Termius - <content>" prefix format first (macOS)
        if raw.lowercased().hasPrefix("termius - ") {
            let content = String(raw.dropFirst("Termius - ".count)).trimmingCharacters(in: .whitespaces)
            if !content.isEmpty { return content }
        }

        // Try "<content> - Termius" suffix format (Windows)
        if let dashRange = raw.range(of: " - ", options: .backwards) {
            let suffix = raw[dashRange.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
            if suffix == "termius" {
                let content = String(raw[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { return content }
            }
        }

        return raw
    }

    private static func sanitizeHost(_ raw: String) -> String {
        let hostPart: String
        if let atIndex = raw.lastIndex(of: "@") {
            hostPart = String(raw[raw.index(after: atIndex)...])
        } else {
            hostPart = raw
        }

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
        if trimmed.contains(":") && trimmed.range(of: ipv6Pattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }
}
