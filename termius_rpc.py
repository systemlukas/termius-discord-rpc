"""
Termius Discord Rich Presence

Privacy-first Rich Presence for Termius. Uses Windows UI Automation to detect
the active Termius view and psutil to confirm SSH sessions. All strings,
privacy flags, assets, and the Discord client ID are configured via config.json.
"""

import time
import psutil
from pypresence import Presence
import sys
import os
import socket
from typing import Optional, Dict, List, Tuple
import json

try:
    import uiautomation as auto  # type: ignore
except Exception:
    auto = None

# Privacy and detection preferences (populated from config.json)
PREFER_UI_LABEL = False
EXPOSE_IP_IN_PRESENCE = False
ALLOW_REVERSE_DNS = False

def _is_generic_label(text: str) -> bool:
    t = (text or '').strip().lower()
    if not t:
        return True
    generic = {
        'termius', 'live', 'close', 'minimize', 'maximize', 'settings', 'search',
        'new tab', 'new host', 'sftp', 'files', 'terminal', 'ssh', 'hosts', 'groups',
        'local', 'actions', 'filter', 'root'
    }
    return t in generic

def _load_config() -> Dict:
    """Load config.json. If missing, create a template and exit. If present but incomplete,
    backfill missing keys into the file and load the merged config."""
    template = {
        "discord_client_id": "YOUR_DISCORD_CLIENT_ID",
        "update_interval_seconds": 5,
        "privacy": {
            "prefer_ui_label": True,
            "expose_ip_in_presence": False,
            "allow_reverse_dns": False
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
            "state_active_ssh": "Active SSH session",
            "details_idle": "No active connections"
        }
    }

    base_dir = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(base_dir, 'config.json')

    # Create config if missing, then exit so the user can review
    if not os.path.exists(path):
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(template, f, indent=2)
        print(f"Created '{path}'. Please set your discord_client_id and adjust settings.")
        sys.exit(1)

    # Load and backfill any missing keys into the file
    with open(path, 'r', encoding='utf-8') as f:
        try:
            cfg = json.load(f)
        except Exception as e:
            print(f"Error reading config.json: {e}")
            sys.exit(1)

    changed = False
    for k, v in template.items():
        if k not in cfg:
            cfg[k] = v
            changed = True
    for nested in ("privacy", "assets", "texts"):
        if nested not in cfg or not isinstance(cfg[nested], dict):
            cfg[nested] = template[nested]
            changed = True
        else:
            for k, v in template[nested].items():
                if k not in cfg[nested]:
                    cfg[nested][k] = v
                    changed = True

    if changed:
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(cfg, f, indent=2)

    return cfg

def is_termius_running():
    """Check if Termius is currently running."""
    for proc in psutil.process_iter(['name']):
        name = (proc.info.get('name') or '').lower()
        if 'termius' in name:
            return True
    return False

def _find_termius_processes() -> List[psutil.Process]:
    """Return a list of running Termius processes."""
    procs: List[psutil.Process] = []
    for proc in psutil.process_iter(['name']):
        try:
            name = (proc.info.get('name') or '').lower()
            if 'termius' in name:
                procs.append(proc)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return procs

def _get_active_session_via_net() -> Optional[Dict[str, str]]:
    """Best-effort detection of the current Termius SSH session using network connections.

    Returns a dict with keys: hostname (IP if unknown), username (if known), port, protocol.
    """
    termius_procs = _find_termius_processes()
    term_pids = {p.pid for p in termius_procs}
    candidate: Optional[Tuple[str, int]] = None  # (ip, port)

    # First try system-wide net connections filtered by Termius PIDs
    try:
        for c in psutil.net_connections(kind='tcp'):
            try:
                if c.pid not in term_pids:
                    continue
                if c.status != psutil.CONN_ESTABLISHED:
                    continue
                if not c.raddr:
                    continue
                rip = c.raddr.ip
                rport = c.raddr.port
                if rport in (22, 2222, 2200, 2022):
                    candidate = (rip, rport)
                    break
            except Exception:
                continue
    except Exception:
        pass

    # Fallback: query each Termius process individually if allowed
    if not candidate:
        for tp in termius_procs:
            try:
                conns = tp.connections(kind='tcp')
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
            for c in conns:
                if c.status != psutil.CONN_ESTABLISHED:
                    continue
                if not c.raddr:
                    continue
                rip = c.raddr.ip
                rport = c.raddr.port
                if rport in (22, 2222, 2200, 2022):
                    candidate = (rip, rport)
                    break
            if candidate:
                break

    if not candidate:
        return None

    rip, rport = candidate
    # Respect privacy preferences: do not expose IP as hostname unless explicitly allowed
    host_val = ''
    if EXPOSE_IP_IN_PRESENCE:
        host_val = rip
    elif ALLOW_REVERSE_DNS:
        try:
            host_val = socket.gethostbyaddr(rip)[0] or ''
        except Exception:
            host_val = ''
    session: Dict[str, str] = {
        'hostname': host_val,  # may be empty to avoid leaking IPs
        'ip': rip,             # keep internally for session continuity only
        'username': '',
        'port': str(rport),
        'protocol': 'SSH' if rport in (22, 2222, 2200, 2022) else 'TCP',
        'mode': 'SSH'
    }
    return session

def _get_active_session_via_ui() -> Optional[Dict[str, str]]:
    """Best-effort UI parsing of the active Termius view and label."""
    if auto is None:
        return None
    try:
        win = auto.WindowControl(searchDepth=1, Name='Termius')
        if not win.Exists(0.2):
            wins = auto.GetRootControl().GetChildren()
            win = next((w for w in wins if 'Termius' in (w.Name or '')), None)
            if not win:
                return None

        label_text = ''
        mode = 'OTHER'
        try:
            win_title = (win.Name or '').strip()
            if ' - ' in win_title:
                possible = win_title.split(' - ', 1)[1].strip()
                if possible and not _is_generic_label(possible):
                    label_text = possible
            title_low = (win.Name or '').lower()
            if any(k in title_low for k in ('settings', 'account', 'preferences', 'keychain', 'port forwarding', 'known hosts')):
                mode = 'SETTINGS'
            elif any(k in title_low for k in ('hosts', 'host list', 'groups')):
                mode = 'BROWSING'
            elif 'sftp' in title_low or 'files' in title_low:
                mode = 'SFTP'
            elif 'snippets' in title_low:
                mode = 'SNIPPETS'
            elif 'logs' in title_low or 'log' in title_low:
                mode = 'LOGS'
        except Exception:
            pass

        if not label_text:
            try:
                descendants = win.GetDescendants()
            except Exception:
                descendants = []

            skip_set = {
                'Termius', 'LIVE', 'Close', 'Minimize', 'Maximize',
                'Settings', 'Search', 'New Tab', 'New Host',
                'SFTP', 'Files', 'Terminal', 'SSH', 'Hosts', 'Groups',
                'Local', 'Actions', 'Filter', 'root'
            }

            candidate_host = ''

            for ctrl in descendants:
                try:
                    if ctrl.ControlTypeName not in ('TabItemControl', 'TextControl', 'ButtonControl'):
                        continue
                    name = (getattr(ctrl, 'Name', '') or '').strip()
                    if not name or name in skip_set:
                        continue
                
                    if any(ch.isalpha() for ch in name) and len(name) <= 60:
                        lowname = name.lower()
                        if not any(k in lowname for k in ('sftp', 'files', 'terminal', 'ssh', 'settings', 'hosts', 'groups', 'local', 'actions', 'filter', 'root')):
                            candidate_host = name
                
                        try:
                            sel_pattern_getter = getattr(ctrl, 'GetSelectionItemPattern', None)
                            if sel_pattern_getter:
                                sel_pattern = sel_pattern_getter()
                                if getattr(sel_pattern, 'IsSelected', False):
                                    if name not in skip_set:
                                        label_text = name
                                    txt_low = name.lower()
                                    if 'sftp' in txt_low or 'files' in txt_low:
                                        mode = 'SFTP'
                                    break
                        except Exception:
                            pass
                        if not label_text:
                            if name not in skip_set:
                                label_text = name
                            txt_low = name.lower()
                            if 'sftp' in txt_low or 'files' in txt_low or 'transfer' in txt_low:
                                mode = 'SFTP'
                    low = name.lower()
                    if any(k in low for k in ('hosts', 'new host', 'groups')):
                        mode = 'BROWSING'
                    if any(k in low for k in ('settings', 'account', 'subscription', 'appearance', 'keychain', 'port forwarding', 'known hosts')):
                        mode = 'SETTINGS'
                    if 'snippets' in low:
                        mode = 'SNIPPETS'
                    if 'logs' in low or low == 'log':
                        mode = 'LOGS'
                except Exception:
                    continue

            if mode == 'SFTP' and not candidate_host:
                try:
                    top_bar: List[str] = []
                    rightmost_name = ''
                    rightmost_left = -1
                    for c in descendants:
                        try:
                            nm = (getattr(c, 'Name', '') or '').strip()
                            if not nm or _is_generic_label(nm):
                                continue
                            if getattr(c, 'ControlTypeName', '') not in ('TabItemControl', 'ButtonControl', 'TextControl'):
                                continue
                            rect = getattr(c, 'BoundingRectangle', None)
                            if not rect:
                                continue
                            if getattr(rect, 'top', getattr(rect, 'Top', 9999)) > 140:
                                continue
                            left = getattr(rect, 'left', getattr(rect, 'Left', -1))
                            if isinstance(left, (int, float)) and left > rightmost_left:
                                rightmost_left = left
                                rightmost_name = nm
                        except Exception:
                            continue
                    if rightmost_name:
                        candidate_host = rightmost_name
                except Exception:
                    pass

            if mode == 'SFTP' and not candidate_host:
                try:
                    tab_names: List[str] = []
                    for c in descendants:
                        try:
                            if getattr(c, 'ControlTypeName', '') != 'TabItemControl':
                                continue
                            nm = (getattr(c, 'Name', '') or '').strip()
                            if nm and not _is_generic_label(nm) and any(ch.isalpha() for ch in nm):
                                tab_names.append(nm)
                        except Exception:
                            continue
                    if tab_names:
                        candidate_host = tab_names[-1]
                except Exception:
                    pass

            if mode == 'SFTP' and not candidate_host:
                try:
                    sftp_ctrl = next((c for c in descendants if (getattr(c, 'Name', '') or '').strip().lower() == 'sftp'), None)
                    if sftp_ctrl is not None:
                        parent = getattr(sftp_ctrl, 'Parent', None)
                        if parent is not None:
                            siblings = parent.GetChildren()
                            names = [ (getattr(s, 'Name', '') or '').strip() for s in siblings ]
                            try:
                                idx = [n.lower() for n in names].index('sftp')
                                for j in range(idx+1, len(siblings)):
                                    nm = names[j]
                                    if nm and not _is_generic_label(nm):
                                        candidate_host = nm
                                        break
                            except ValueError:
                                pass
                except Exception:
                    pass

        if not label_text:
            # If we detected a non-SSH UI mode, still return it. For SFTP, prefer candidate_host if available.
            if mode in ('SFTP', 'BROWSING', 'SETTINGS'):
                fallback_host = ''
                try:
                    if mode == 'SFTP' and 'candidate_host' in locals() and locals()['candidate_host']:
                        fallback_host = locals()['candidate_host']
                except Exception:
                    fallback_host = ''
                return {
                    'hostname': fallback_host,
                    'username': '',
                    'port': '22',
                    'protocol': 'SSH',
                    'mode': mode
                }
            return None

        username = ''
        hostname = label_text
        if '@' in label_text:
            parts = label_text.split('@', 1)
            if len(parts) == 2:
                username, hostname = parts[0], parts[1]

        # If we are in SFTP mode and the chosen hostname looks generic or empty, use candidate_host if available
        if (mode == 'SFTP'):
            if not hostname or _is_generic_label(hostname):
                try:
                    # use the candidate_host tracked above if present
                    if 'candidate_host' in locals() and locals()['candidate_host']:
                        hostname = locals()['candidate_host']
                except Exception:
                    pass
            # If still generic or empty, leave hostname empty ("SFTP session")
            if _is_generic_label(hostname):
                hostname = ''

        # For non-SSH informational views, do not return hostname to avoid accidental SSH-like text
        if mode in ('SETTINGS', 'SNIPPETS', 'LOGS', 'BROWSING'):
            hostname = ''

        return {
            'hostname': hostname,
            'username': username,
            'port': '22',
            'protocol': 'SSH',  # default; refined by mode when known
            'mode': (
                'SFTP' if mode == 'SFTP' else
                'BROWSING' if mode == 'BROWSING' else
                'SETTINGS' if mode == 'SETTINGS' else
                'SNIPPETS' if mode == 'SNIPPETS' else
                'LOGS' if mode == 'LOGS' else 'SSH'
            )
        }
    except Exception:
        return None


def _is_termius_foreground() -> bool:
    """Return True if the foreground window appears to be Termius.
    If UI Automation is unavailable, assume True (best effort).
    """
    if auto is None:
        return True
    try:
        fg = auto.GetForegroundControl()
        # Climb to the top-level window
        top = fg
        while top and getattr(top, 'Parent', None):
            top = top.Parent
        name = (getattr(top, 'Name', '') or '').lower()
        return 'termius' in name
    except Exception:
        return True


def get_termius_sessions(previous_session: Optional[Dict[str, str]] = None) -> List[Dict[str, str]]:
    """Attempt to detect the current active Termius session with safer logic.

    Rules:
    - Report SSH only if we have a real network connection owned by Termius.
    - If UI shows SFTP/BROWSING/SETTINGS and Termius window is foreground, report that mode.
    - Otherwise, if Termius is open without a connection, return IDLE when foreground is Termius.
    - Fall back to the previous session to avoid flicker only for timing continuity, not to fake SSH.
    """
    ui = _get_active_session_via_ui()
    net = _get_active_session_via_net()

    # If UI explicitly indicates a non-SSH mode, prefer it
    if ui and (ui.get('mode') in ('SFTP', 'BROWSING', 'SETTINGS', 'SNIPPETS', 'LOGS')):
        # Clean up generic hostnames
        if _is_generic_label(ui.get('hostname', '')):
            ui['hostname'] = ''
        return [ui]

    # SSH only when network confirms it
    if net:
        # If UI says SFTP, prefer reporting SFTP (as browsing) even if SSH net is active
        if ui and ui.get('mode') == 'SFTP':
            return [{
                'hostname': '',
                'username': '',
                'port': net.get('port', ''),
                'protocol': 'SSH',
                'mode': 'SFTP'
            }]

        # Otherwise, merge in a non-generic UI-derived hostname if available (for privacy-friendly label)
        if ui and ui.get('hostname') and not _is_generic_label(ui.get('hostname', '')):
            net['hostname'] = ui['hostname']
            net['username'] = ui.get('username', '')
        return [net]

    # If Termius is foreground but no SSH connection, report IDLE or keep UI mode
    if _is_termius_foreground():
        if ui:
            if ui.get('mode') not in ('SFTP', 'BROWSING', 'SETTINGS', 'SNIPPETS', 'LOGS'):
                ui['mode'] = 'IDLE'
            return [ui]
        else:
            return [{
                'hostname': '',
                'username': '',
                'port': '',
                'protocol': 'SSH',
                'mode': 'IDLE'
            }]

    # Not foreground and no connection -> no active session
    return []

def main():
    # Load configuration
    cfg = _load_config()
    # Update global privacy flags
    try:
        global PREFER_UI_LABEL, EXPOSE_IP_IN_PRESENCE, ALLOW_REVERSE_DNS
        PREFER_UI_LABEL = bool(cfg.get('privacy', {}).get('prefer_ui_label', PREFER_UI_LABEL))
        EXPOSE_IP_IN_PRESENCE = bool(cfg.get('privacy', {}).get('expose_ip_in_presence', EXPOSE_IP_IN_PRESENCE))
        ALLOW_REVERSE_DNS = bool(cfg.get('privacy', {}).get('allow_reverse_dns', ALLOW_REVERSE_DNS))
    except Exception:
        pass

    # Initialize Discord RPC
    client_id = str(cfg.get('discord_client_id', '')).strip()
    if not client_id or client_id.upper() == 'YOUR_DISCORD_CLIENT_ID':
        print("Error: Please set 'discord_client_id' in config.json to your Discord Application Client ID.")
        sys.exit(1)
    RPC = Presence(client_id)
    
    try:
        RPC.connect()
        print("Connected to Discord RPC")
        
        # Track session continuity for stable start timestamps
        current_key: Optional[str] = None
        session_start_ts: Optional[int] = None
        previous_session: Optional[Dict[str, str]] = None

        while True:
            if is_termius_running():
                sessions = get_termius_sessions(previous_session=previous_session)
                if sessions:
                    session = sessions[0]
                    previous_session = session
                    # Build a key representing the session identity
                    uname = session.get('username') or ''
                    host = session.get('hostname') or ''
                    # Use IP only for identity continuity, never for display
                    internal_ip = session.get('ip') or ''
                    proto = session.get('protocol') or 'SSH'
                    identity_host = host if host else internal_ip
                    key = f"{proto}:{uname}@{identity_host}" if uname else f"{proto}:{identity_host}"

                    # Preserve the start time if we're still on the same session
                    if key != current_key:
                        current_key = key
                        session_start_ts = int(time.time())

                    # Human-friendly state/details based on mode
                    mode = (session.get('mode') or 'SSH').upper()

                    details = cfg.get('texts', {}).get('details_connected', "Connected via Termius")
                    if mode == 'SFTP':
                        state = cfg.get('texts', {}).get('state_sftp', "Browsing in SFTP")
                    elif mode == 'BROWSING':
                        state = cfg.get('texts', {}).get('state_browsing', "Browsing for servers")
                        details = cfg.get('texts', {}).get('details_hosts', "Termius Hosts")
                    elif mode == 'SETTINGS':
                        state = cfg.get('texts', {}).get('state_settings', "Viewing settings")
                        details = cfg.get('texts', {}).get('details_settings', "Termius Settings")
                    elif mode == 'SNIPPETS':
                        state = cfg.get('texts', {}).get('state_snippets', "Viewing Snippets")
                        details = cfg.get('texts', {}).get('details_snippets', "Termius Snippets")
                    elif mode == 'LOGS':
                        state = cfg.get('texts', {}).get('state_logs', "Viewing logs")
                        details = cfg.get('texts', {}).get('details_logs', "Termius Logs")
                    elif mode == 'IDLE':
                        state = cfg.get('texts', {}).get('state_idle', "Idle in Termius")
                        details = "No active connections"
                    else:
                        if uname and host:
                            state = f"SSH to {uname}@{host}"
                        elif host:
                            state = f"SSH to {host}"
                        else:
                            state = cfg.get('texts', {}).get('state_active_ssh', "Active SSH session")

                    RPC.update(
                        state=state,
                        details=details,
                        large_image=cfg.get('assets', {}).get('large_image', 'termius'),
                        large_text=cfg.get('assets', {}).get('large_text', 'Termius SSH Client'),
                        small_image=cfg.get('assets', {}).get('small_image', 'ssh_icon'),
                        small_text=session.get('protocol', 'SSH'),
                        start=session_start_ts or int(time.time())
                    )
                else:
                    RPC.update(
                        state=cfg.get('texts', {}).get('state_idle', "Idle in Termius"),
                        details="No active connections",
                        large_image=cfg.get('assets', {}).get('large_image', 'termius'),
                        large_text=cfg.get('assets', {}).get('large_text', 'Termius SSH Client')
                    )
            else:
                RPC.clear()
                current_key = None
                session_start_ts = None
                print("Termius is not running. Waiting...")
                
            time.sleep(int(cfg.get('update_interval_seconds', 5)))  # configurable update interval
            
    except KeyboardInterrupt:
        print("Disconnecting from Discord RPC...")
        RPC.close()
    except Exception as e:
        print(f"An error occurred: {e}")
        RPC.close()
        sys.exit(1)

if __name__ == "__main__":
    print("Starting Termius Discord Rich Presence...")
    print("Press Ctrl+C to exit")
    main()
