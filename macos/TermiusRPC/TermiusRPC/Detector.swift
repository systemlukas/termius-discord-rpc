import AppKit
import CoreGraphics

final class TermiusDetector {
    /// Detect the current Termius state by checking processes and window titles.
    func detect() -> TermiusState {
        guard let app = findTermiusProcess() else {
            return .closed
        }

        let title = getWindowTitle(pid: app.processIdentifier)
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
    /// Uses .optionAll to catch windows even when Termius is in the background.
    private func getWindowTitle(pid: pid_t) -> String? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        // Filter to Termius windows on the normal layer (0) with non-empty titles
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
}
