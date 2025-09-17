# Termius Discord Rich Presence

Privacy-first Discord Rich Presence for Termius, with smart UI detection and easy configuration.

## What it does

- Shows Termius status and updates your Discord presence automatically
- SSH sessions: displays `SSH to <host>` (never shows raw IPs unless you enable it)
- Non-SSH views with clear text:
  - SFTP: `Browsing in SFTP`
  - Hosts list: `Browsing for servers`
  - Settings / Keychain / Port Forwarding / Known Hosts: `Viewing settings`
  - Snippets: `Viewing Snippets`
  - Logs: `Viewing logs`
- Clears presence when Termius is closed

## Prerequisites
- Python 3.8+
- Discord desktop app running
- Termius installed
- Windows: UI detection uses `uiautomation` (already in `requirements.txt`)

## Install
1. Clone or download this repository
2. Install deps:
   ```bash
   pip install -r requirements.txt
   ```
3. Create a Discord Application and upload Rich Presence assets:
   - [Discord Developer Portal](https://discord.com/developers/applications)
   - Create an app, copy the Client ID
   - Under Rich Presence, upload images and name them (e.g. `termius`, `ssh_icon`)
4. Configure via `config.json` (see below)

## Configuration: `config.json`
All settings live in `config.json` at the project root. A default was created for you:
```json
{
  "discord_client_id": "1417890882702540911",
  "update_interval_seconds": 5,
  "privacy": {
    "prefer_ui_label": true,
    "expose_ip_in_presence": false,
    "allow_reverse_dns": false
  },
  "assets": {
    "large_image": "termius",
    "large_text": "Termius SSH Client",
    "small_image": "ssh_icon"
  },
  "texts": {
    "details_connected": "Connected via Termius",
    "details_hosts": "Termius Hosts",
    "details_settings": "Termius Settings",
    "details_snippets": "Termius Snippets",
    "details_logs": "Termius Logs",
    "state_sftp": "Browsing in SFTP",
    "state_browsing": "Browsing for servers",
    "state_settings": "Viewing settings",
    "state_snippets": "Viewing Snippets",
    "state_logs": "Viewing logs",
    "state_idle": "Idle in Termius",
    "state_active_ssh": "Active SSH session"
  }
}
```
- `discord_client_id`: your Discord app Client ID
- `update_interval_seconds`: how often we update the presence
- `privacy`: control whether to prefer UI labels and whether IP reverse DNS is allowed
- `assets`: names must match the images you uploaded in your Discord app
- `texts`: override any UI string to your own wording

## Usage
1. Ensure Discord is running
2. Start the script:
   ```bash
   python termius_rpc.py
   ```
3. Open Termius and switch tabs — your Discord presence will update every few seconds
4. Press Ctrl+C to stop

## How detection works (privacy-first)
- Uses Windows UI Automation to read Termius’ active window/tab names
- For SSH, confirms there’s a real TCP connection from a Termius process before showing `SSH to ...`
- Raw IPs are not displayed by default. You can enable reverse DNS if you prefer hostnames where available

## Troubleshooting
- Presence not updating? Check that the Discord desktop app is running
- No images? Make sure `assets.large_image` and `assets.small_image` match the names you uploaded in the Discord Developer Portal
- Wrong wording? Tweak any label in `config.json → texts` and restart the script

## License
MIT
