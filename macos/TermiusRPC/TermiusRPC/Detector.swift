import AppKit
import CoreGraphics

final class TermiusDetector {
    /// Whether we've already shown the permission prompt this session.
    private var hasPromptedForPermission = false

    /// Detect the current Termius state by checking processes and window titles.
    func detect() -> TermiusState {
        guard let app = findTermiusProcess() else {
            return .closed
        }

        let title = getWindowTitle(pid: app.processIdentifier)

        // If Termius is running with on-screen windows but we got no titles,
        // we likely lack Screen Recording permission.
        if title == nil || title == "" {
            if !hasPromptedForPermission && hasOnScreenWindows(pid: app.processIdentifier) {
                hasPromptedForPermission = true
                promptForScreenRecordingPermission()
            }
        }

        return TitleParser.parse(title)
    }

    /// Check if Termius is currently running.
    private func findTermiusProcess() -> NSRunningApplication? {
        let knownBundleIDs = [
            "com.termius.mac",         // Mac App Store
            "com.termius.Termius",     // Direct download variant
            "com.termius-dmg.mac",     // DMG install variant
        ]
        for bundleID in knownBundleIDs {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let app = apps.first { return app }
        }

        // Fallback: search by name, but exclude ourselves
        let ownBundleID = Bundle.main.bundleIdentifier ?? "com.systemlukas.termiusrpc"
        return NSWorkspace.shared.runningApplications.first { app in
            let name = (app.localizedName ?? "").lowercased()
            let bundleID = app.bundleIdentifier ?? ""
            return name.contains("termius") && bundleID != ownBundleID
        }
    }

    /// Get the title of the frontmost Termius window using CGWindowList.
    private func getWindowTitle(pid: pid_t) -> String? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let termiusWindows = windowList.filter { info in
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t
            let layer = info[kCGWindowLayer as String] as? Int
            return ownerPID == pid && layer == 0
        }

        // Prefer on-screen windows with titles, then any window with a title
        let onScreen = termiusWindows.filter {
            ($0[kCGWindowIsOnscreen as String] as? Bool) == true
        }

        for window in onScreen {
            if let name = window[kCGWindowName as String] as? String, !name.isEmpty {
                return name
            }
        }

        for window in termiusWindows {
            if let name = window[kCGWindowName as String] as? String, !name.isEmpty {
                return name
            }
        }

        return termiusWindows.isEmpty ? nil : ""
    }

    /// Check if Termius has visible windows (even if we can't read their titles).
    private func hasOnScreenWindows(pid: pid_t) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        return windowList.contains { info in
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t
            let layer = info[kCGWindowLayer as String] as? Int
            return ownerPID == pid && layer == 0
        }
    }

    /// Show an alert guiding the user to grant Screen Recording permission.
    private func promptForScreenRecordingPermission() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "TermiusRPC needs Screen Recording access to read Termius window titles and detect your SSH sessions.\n\nPlease enable TermiusRPC in:\nSystem Settings → Privacy & Security → Screen Recording"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                // Open Screen Recording settings directly
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
