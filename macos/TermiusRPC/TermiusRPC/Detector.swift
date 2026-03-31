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
            "com.termius.mac",
            "com.termius.Termius",
        ]
        for bundleID in knownBundleIDs {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let app = apps.first { return app }
        }

        return NSWorkspace.shared.runningApplications.first { app in
            (app.localizedName ?? "").lowercased().contains("termius")
        }
    }

    /// Get the title of the frontmost Termius window using CGWindowList.
    private func getWindowTitle(pid: pid_t) -> String? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let termiusWindows = windowList.filter { info in
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t
            let layer = info[kCGWindowLayer as String] as? Int
            return ownerPID == pid && layer == 0
        }

        for window in termiusWindows {
            if let name = window[kCGWindowName as String] as? String, !name.isEmpty {
                return name
            }
        }

        return termiusWindows.isEmpty ? nil : ""
    }
}
