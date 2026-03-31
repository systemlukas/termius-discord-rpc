# Termius Discord Rich Presence

Privacy-first Discord Rich Presence for Termius. Native apps for macOS, Windows, and Linux.

## Features

- Shows your Termius activity in Discord automatically
- **SSH sessions**: displays `SSH to <host>` (never shows raw IPs)
- **SFTP**: displays `Browsing in SFTP`
- **Idle**: shows when Termius is open but inactive
- Clears presence when Termius is closed
- System tray app with settings GUI
- Zero setup: download, run, done

## Download

Grab the latest release for your platform from [GitHub Releases](https://github.com/systemlukas/termius-discord-rpc/releases).

| Platform | File | Requirements |
|----------|------|--------------|
| macOS | `TermiusRPC-macOS.zip` | macOS 13+ (Ventura) |
| Windows | Coming soon | Windows 10+ |
| Linux | Coming soon | Ubuntu 22.04+ |

## macOS

1. Download and unzip `TermiusRPC-macOS.zip`
2. Move `TermiusRPC.app` to `/Applications`
3. Double-click to run (right-click > Open on first launch if unsigned)
4. A terminal icon appears in your menu bar

### Permissions

- **Screen Recording** (macOS 14+): Required to read Termius window titles. Grant in System Settings > Privacy & Security > Screen Recording.
- Without this permission, the app can only detect if Termius is running (idle/closed), not what you're doing.

### Settings

Click the menu bar icon > Settings to configure:
- **Start on login**: auto-launch at login
- **Update interval**: how often to poll (1-60 seconds)
- **Show hostname**: toggle hostname display in presence
- **Show SFTP status**: toggle SFTP detection

Config is stored in `~/Library/Application Support/TermiusRPC/config.json`.

## Privacy

- No network calls except local Discord IPC (Unix socket)
- No telemetry, analytics, or update checks
- IP addresses are never displayed
- Hostname display is configurable
- Window titles are read locally and never transmitted

## Architecture

Three separate native apps sharing a common behavioral spec:

| Platform | Language | UI Framework | Window Detection |
|----------|----------|-------------|-----------------|
| macOS | Swift | SwiftUI MenuBarExtra | CGWindowListCopyWindowInfo |
| Windows | C# / .NET 8 | WPF + NotifyIcon | UIAutomation |
| Linux | Go | GTK3 + AppIndicator | X11 / Wayland |

## Development

### macOS

```bash
cd macos
swift build        # build
swift test         # run tests (36 tests)
swift build -c release  # release build
```

## License

MIT
