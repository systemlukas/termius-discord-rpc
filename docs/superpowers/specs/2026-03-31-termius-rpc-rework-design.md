# Termius Discord Rich Presence — Full Rework Design Spec

**Date:** 2026-03-31
**Status:** Draft

## Overview

Three native platform-specific applications that detect Termius state and display it as Discord Rich Presence. Each app is a background daemon with a system tray icon and a small native settings GUI. Zero setup for users — download, run, done.

## Platforms & Tech Stacks

### macOS — Swift + SwiftUI

- **App type:** Menu bar agent (LSUIElement, no dock icon)
- **Tray:** NSStatusItem with popover menu
- **Settings UI:** SwiftUI popover/window from menu bar icon
- **Window detection:** CoreGraphics `CGWindowListCopyWindowInfo` to get Termius window titles, supplemented by Accessibility API (AXUIElement) for deeper tab/view inspection
- **Distribution:** `.zip` containing signed `.app` bundle (GitHub Release)
- **Auto-start:** `SMAppService` (Login Items API, macOS 13+), fallback to LaunchAgent plist for older macOS
- **Min target:** macOS 13 (Ventura)

### Windows — C# / .NET 8

- **App type:** Windows Forms NotifyIcon tray application
- **Tray:** NotifyIcon with context menu
- **Settings UI:** WPF window launched from tray context menu
- **Window detection:** `System.Windows.Automation` (UIAutomation) to read Termius window/tab names
- **Distribution:** Single-file self-contained `.exe` (no .NET runtime required)
- **Auto-start:** Registry key `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- **Min target:** Windows 10 (21H2+)

### Linux — Go + GTK3

- **App type:** GTK3 application with AppIndicator tray icon
- **Tray:** libappindicator3 (systray)
- **Settings UI:** GTK3 dialog launched from tray menu
- **Window detection:**
  - X11: `XGetWindowProperty` via `_NET_WM_NAME` (or shelling out to `xdotool getactivewindow getwindowname`)
  - Wayland: `wlr-foreign-toplevel-management` protocol where supported, fallback to D-Bus / compositor-specific APIs
- **Distribution:** AppImage (single portable binary)
- **Auto-start:** `.desktop` file in `~/.config/autostart/`
- **Min target:** Ubuntu 22.04+ / Fedora 38+ equivalent

## Shared Behavior Spec

All three implementations MUST behave identically per this spec.

### Discord Application

- **Client ID:** Baked into the binary (shipped by us, not user-configurable by default)
- **Assets:** `termius` (large image), `ssh_icon` (small image) — uploaded to the Discord Developer Portal under our app
- **IPC:** Discord communicates via local IPC (Unix domain socket on macOS/Linux at `$XDG_RUNTIME_DIR/discord-ipc-0` or `/tmp/discord-ipc-0`, named pipe `\\.\pipe\discord-ipc-0` on Windows)

### State Machine

```
┌─────────────────┐
│ Termius Closed   │──── Clear Discord presence
└─────────────────┘
         │ (Termius process detected)
         v
┌─────────────────┐
│ Idle             │──── details: "Termius", state: "Idle"
└─────────────────┘
         │ (SSH connection detected via window title)
         v
┌─────────────────┐
│ SSH Active       │──── details: "Connected via Termius", state: "SSH to <label>"
└─────────────────┘
         │ (SFTP view detected via window title)
         v
┌─────────────────┐
│ SFTP Active      │──── details: "Connected via Termius", state: "Browsing in SFTP"
└─────────────────┘
```

**Transitions:**
- Poll every 5 seconds (configurable)
- Only update Discord when state actually changes (avoid unnecessary IPC calls)
- Elapsed timer starts when entering a new state (SSH/SFTP), resets on state change
- When Termius closes, clear presence immediately (don't wait for next poll)

### Detection Logic

**Step 1: Is Termius running?**
- Check running processes for a process named `Termius` (case-insensitive match)
- If not running → state = CLOSED → clear presence

**Step 2: What is the active Termius window showing?**
- Read the Termius window title using platform-native API
- Parse title to determine mode:

| Window title contains | State |
|---|---|
| `SFTP` or `Files` | SFTP |
| Pattern: `<user>@<host>` or known SSH label | SSH (extract label) |
| Anything else (settings, hosts, snippets, etc.) | IDLE |

**Step 3: For SSH, extract the display label**
- Use the window title / tab name as the label (e.g., "homelab", "user@myserver")
- NEVER show raw IP addresses — if the title is just an IP, show "Active SSH session" instead
- IP detection regex: `^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$` (also check for IPv6 patterns)

### Presence Display

| State | `details` field | `state` field | Large image | Small image | Timestamp |
|---|---|---|---|---|---|
| SSH | "Connected via Termius" | "SSH to \<label\>" | `termius` | `ssh_icon` | Elapsed since SSH start |
| SFTP | "Connected via Termius" | "Browsing in SFTP" | `termius` | `ssh_icon` | Elapsed since SFTP start |
| Idle | "Termius" | "Idle" | `termius` | none | none |
| Closed | (cleared) | (cleared) | — | — | — |

### Configuration

Stored in platform-appropriate location:
- **macOS:** `~/Library/Application Support/TermiusRPC/config.json`
- **Windows:** `%APPDATA%\TermiusRPC\config.json`
- **Linux:** `~/.config/termius-rpc/config.json`

**Config schema:**
```json
{
  "update_interval_seconds": 5,
  "start_on_login": true,
  "privacy": {
    "show_hostname": true,
    "show_sftp_status": true
  }
}
```

- `update_interval_seconds` — polling interval (min: 1, max: 60, default: 5)
- `start_on_login` — whether the app registers itself to auto-start (default: true)
- `privacy.show_hostname` — if false, SSH always shows "Active SSH session" instead of the host label
- `privacy.show_sftp_status` — if false, SFTP shows as generic "Idle" instead of "Browsing in SFTP"

Config is watched for changes (fsnotify/kqueue/inotify). No restart needed after editing.

### Settings GUI

Accessible from system tray right-click menu → "Settings".

**Fields:**
- Toggle: "Start on login" (on/off)
- Slider/input: "Update interval" (1–60 seconds)
- Toggle: "Show hostname in presence"
- Toggle: "Show SFTP status"
- Label: Current status (e.g., "Connected — SSH to homelab")
- Button: "Quit"

Minimal, clean, native-looking. No unnecessary chrome.

### Tray Menu

Right-click (or left-click on macOS) the tray icon:

```
Status: SSH to homelab          (greyed out, informational)
────────────────────
Settings...                     (opens settings window)
Start on Login          ✓       (toggle)
────────────────────
Quit
```

### Error Handling

- **Discord not running:** Retry connection every 30 seconds silently. No error popup. Show "Discord not connected" in tray tooltip.
- **Termius not running:** Normal state — just clear presence. No error.
- **Config file corrupt:** Fall back to defaults, log warning.
- **Accessibility permissions (macOS):** If not granted, show a one-time notification guiding user to System Settings → Privacy & Security → Accessibility. Detection falls back to process-only (Idle/Closed).
- **No X11/Wayland (Linux):** Fall back to process-only detection (Idle/Closed).

### Privacy

- No network calls except Discord IPC (which is local)
- No telemetry, no analytics, no update checks
- IP addresses are never displayed in presence
- Hostname display is opt-out via config
- Window titles are read locally and never transmitted anywhere

## Repository Structure

```
termius-discord-rpc/
├── macos/                      # Xcode project
│   ├── TermiusRPC.xcodeproj/
│   ├── TermiusRPC/
│   │   ├── App.swift           # Entry point, menu bar setup
│   │   ├── StatusBarController.swift  # Tray icon + menu
│   │   ├── SettingsView.swift  # SwiftUI settings
│   │   ├── Config.swift        # Config load/save/watch
│   │   ├── DiscordRPC.swift    # Discord IPC client
│   │   ├── Detector.swift      # Window title detection (CG + AX)
│   │   └── StateMachine.swift  # State transitions
│   └── Assets.xcassets/        # App icon, tray icon
│
├── windows/                    # .NET solution
│   ├── TermiusRPC.sln
│   ├── TermiusRPC/
│   │   ├── Program.cs          # Entry point, tray setup
│   │   ├── TrayIcon.cs         # NotifyIcon + context menu
│   │   ├── SettingsWindow.xaml # WPF settings
│   │   ├── Config.cs           # Config load/save/watch
│   │   ├── DiscordRpc.cs       # Discord IPC client (named pipe)
│   │   ├── Detector.cs         # UIAutomation window detection
│   │   └── StateMachine.cs     # State transitions
│   └── Assets/                 # Icons
│
├── linux/                      # Go module
│   ├── go.mod
│   ├── go.sum
│   ├── main.go                 # Entry point, tray setup
│   ├── tray.go                 # AppIndicator tray
│   ├── settings.go             # GTK3 settings dialog
│   ├── config.go               # Config load/save/watch
│   ├── discord.go              # Discord IPC client (unix socket)
│   ├── detector_x11.go         # X11 window detection
│   ├── detector_wayland.go     # Wayland window detection
│   └── state.go                # State transitions
│
├── shared/
│   └── spec.md                 # This behavioral spec (canonical reference)
│
├── assets/
│   ├── icon.png                # App icon (1024x1024)
│   ├── tray-icon.png           # Tray icon (22x22, 44x44)
│   ├── tray-icon-dark.png      # Tray icon for dark themes
│   └── discord/
│       ├── termius.png         # Large presence image
│       └── ssh_icon.png        # Small presence image
│
├── .github/
│   └── workflows/
│       ├── build-macos.yml     # Build + sign .app, upload to release
│       ├── build-windows.yml   # Build self-contained .exe, upload
│       ├── build-linux.yml     # Build AppImage, upload
│       └── release.yml         # Create GitHub release, trigger builds
│
└── README.md
```

## CI/CD & Distribution

### GitHub Actions

- **On tag push** (e.g., `v1.0.0`): create a GitHub Release draft, trigger all three build workflows
- **macOS:** Build on `macos-latest`, produce `TermiusRPC-macOS.zip` containing `TermiusRPC.app`
- **Windows:** Build on `windows-latest`, produce `TermiusRPC-Windows.exe` (single file)
- **Linux:** Build on `ubuntu-latest`, produce `TermiusRPC-Linux.AppImage`
- All three artifacts attached to the release

### Code Signing

- **macOS:** Ad-hoc signing initially (users may need to right-click → Open on first launch). Proper Developer ID signing later if needed.
- **Windows:** Unsigned initially. SmartScreen warning on first run. Code signing certificate later if needed.
- **Linux:** No signing needed for AppImage.

## Out of Scope

- Auto-update mechanism (users download new releases manually)
- Multiple simultaneous SSH session tracking (show only the active/foreground one)
- Custom Discord app ID override (may add later)
- Localization / i18n
- Network-based SSH detection (window title only)
