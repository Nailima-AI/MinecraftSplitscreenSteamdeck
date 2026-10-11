#!/usr/bin/env python3
# --- Minecraft Splitscreen Steam Shortcut Adder ---
# This script adds a custom Minecraft Splitscreen launcher to Steam's shortcuts.vdf,
# and downloads SteamGridDB artwork for a polished look in your Steam library.
# It is designed to work for any Linux user (not just Steam Deck).
#
# Based on the original script by ArnoldSmith86:
# https://github.com/ArnoldSmith86/minecraft-splitscreen
# Modified and improved for portability and clarity.

import os
import re
import struct
import zlib
import urllib.request
import tempfile
from pathlib import Path

# --- Config: Set up paths and app info dynamically for the current user ---
HOME = os.path.expanduser("~")  # Get the current user's home directory
APPNAME  = "Minecraft Splitscreen"  # Name as it will appear in Steam

# Detect PrismLauncher paths for splitscreen gameplay.
def detect_launcher():
    """Detect PrismLauncher launcher for splitscreen gameplay."""
    launcher_path = f"{HOME}/.local/share/minecraft-splitscreen/PrismLauncher/PrismLauncher.AppImage"
    launcher_script = f"{HOME}/.local/share/minecraft-splitscreen/PrismLauncher/minecraftSplitscreen.sh"

    if os.path.exists(launcher_script):
        return launcher_script, f"{HOME}/.local/share/minecraft-splitscreen/PrismLauncher", "PrismLauncher"

    if os.path.exists(launcher_path) and os.access(launcher_path, os.X_OK):
        print("❌ Error: PrismLauncher was found, but minecraftSplitscreen.sh is missing.")
        print("   Re-run the installer to restore the launcher script.")
        exit(1)

    print("❌ Error: PrismLauncher install not found!")
    print("   Please run the Minecraft Splitscreen installer to set up PrismLauncher")
    exit(1)

EXE, STARTDIR, LAUNCHER_NAME = detect_launcher()
print(f"📱 Detected launcher: {LAUNCHER_NAME}")
print(f"🚀 Launch script: {EXE}")
print(f"📁 Working directory: {STARTDIR}")

# SteamGridDB artwork URLs for custom grid images, hero, logo, and icon
STEAMGRIDDB_IMAGES = {
    "p": "https://cdn2.steamgriddb.com/grid/a73027901f88055aaa0fd1a9e25d36c7.png",  # Portrait grid
    "": "https://cdn2.steamgriddb.com/grid/e353b610e9ce20f963b4cca5da565605.jpg",      # Main grid
    "_hero": "https://cdn2.steamgriddb.com/hero/ecd812da02543c0269cfc2c56ab3c3c0.png", # Hero image
    "_logo": "https://cdn2.steamgriddb.com/logo/90915208c601cc8c86ad01250ee90c12.png", # Logo
    "_icon": "https://cdn2.steamgriddb.com/icon/add7a048049671970976f3e18f21ade3.ico"   # Icon
}

# --- Locate Steam shortcuts file for the current user ---
userdata = os.path.expanduser("~/.steam/steam/userdata")  # Steam userdata directory
user_ids = sorted(d for d in os.listdir(userdata) if d.isdigit() and os.path.isdir(os.path.join(userdata, d)))
user_id = os.environ.get("MSS_STEAM_USER_ID")
if user_id and user_id not in user_ids:
    raise SystemExit("MSS_STEAM_USER_ID does not match an existing Steam userdata directory.")
if not user_id and len(user_ids) > 1:
    raise SystemExit("Multiple Steam users found. Set MSS_STEAM_USER_ID to the intended userdata directory name.")
user_id = user_id or (user_ids[0] if user_ids else None)
if not user_id:
    print("❌ No Steam user found.")
    exit(1)
config_dir = os.path.join(userdata, user_id, "config")  # Path to config directory
shortcuts_file = os.path.join(config_dir, "shortcuts.vdf")  # Path to shortcuts.vdf
os.makedirs(config_dir, exist_ok=True)
# A running client can overwrite changes. Do not modify another user's session.
for process in Path("/proc").iterdir():
    if not process.name.isdigit():
        continue
    try:
        if process.stat().st_uid == os.getuid() and (process / "comm").read_text().strip() == "steam":
            raise SystemExit("Steam is still running. Close it before adding the shortcut.")
    except (OSError, UnicodeError):
        continue

# --- Ensure shortcuts.vdf exists (create if missing) ---
if os.path.exists(shortcuts_file):
    with open(shortcuts_file, "rb") as f:
        data = f.read()
else:
    data = b'\x00shortcuts\x00\x08\x08'
if not data.startswith(b'\x00shortcuts\x00') or not data.endswith(b'\x08\x08'):
    raise SystemExit("Unrecognized shortcuts.vdf structure; no changes made.")
if EXE.encode() in data:
    print("This launch script already appears in shortcuts.vdf; leaving it unchanged.")
    raise SystemExit(0)

def get_latest_index(data):
    """
    Find the highest shortcut index in the VDF file.
    Steam shortcuts are stored as binary blobs with indices: \x00<index>\x00
    """
    matches = re.findall(rb'\x00(\d+)\x00', data)
    if matches:
        return max(map(int, matches))
    return -1

# --- Determine the next shortcut index ---
index = get_latest_index(data) + 1

# --- Helper: Create a binary shortcut entry for Steam's VDF format ---
def make_entry(index, appid, appname, exe, startdir):
    """
    Build a binary VDF entry for a Steam shortcut.
    Args:
        index (int): Shortcut index
        appid (int): Unique app ID
        appname (str): Name in Steam
        exe (str): Executable path
        startdir (str): Working directory
    Returns:
        bytes: Binary VDF entry
    """
    x00 = b'\x00'; x01 = b'\x01'; x02 = b'\x02'; x08 = b'\x08'
    b = b''
    b += x00 + str(index).encode() + x00  # Shortcut index
    b += x02 + b'appid' + x00 + struct.pack('<I', appid)  # AppID
    b += x01 + b'appname' + x00 + appname.encode() + x00  # App name
    b += x01 + b'exe' + x00 + exe.encode() + x00          # Executable
    b += x01 + b'StartDir' + x00 + startdir.encode() + x00  # Working dir
    b += x01 + b'icon' + x00 + config_dir.encode() + b'/grid/' + str(appid).encode() + b'_icon.ico' + x00  # Icon path
    b += x08  # End of entry
    return b

# --- Generate a unique appid for the shortcut (matches Steam's logic) ---
quoted_exe = f'"{EXE}"'
appid = (zlib.crc32((quoted_exe + APPNAME).encode("utf-8")) | 0x80000000) & 0xFFFFFFFF
entry = make_entry(index, appid, APPNAME, quoted_exe, f'"{STARTDIR}"')

# --- Insert the new shortcut entry before the last two \x08 bytes (end of VDF) ---
if data.endswith(b'\x08\x08'):
    new_data = data[:-2] + entry + b'\x08\x08'
    # Retain a unique backup, then atomically replace within the same filesystem.
    if os.path.exists(shortcuts_file):
        backup_fd, backup = tempfile.mkstemp(prefix="shortcuts.vdf.backup-", dir=config_dir)
        with os.fdopen(backup_fd, "wb") as f:
            f.write(data)
        print(f"Shortcut backup: {backup}")
    temp_fd, temporary = tempfile.mkstemp(prefix=".shortcuts-", dir=config_dir)
    try:
        with os.fdopen(temp_fd, "wb") as f:
            f.write(new_data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary, shortcuts_file)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f"✅ Minecraft shortcut added with index {index} and appid {appid}")
else:
    print("❌ File structure not recognized. No changes made.")
    exit(1)

# --- Download SteamGridDB artwork for the new shortcut ---
grid_dir = os.path.join(userdata, user_id, "config", "grid")  # Path to grid images
os.makedirs(grid_dir, exist_ok=True)  # Ensure grid directory exists

for suffix, url in STEAMGRIDDB_IMAGES.items():
    # Determine file extension based on URL
    path = os.path.join(grid_dir, f"{appid}{suffix}.png" if not url.endswith(".ico") else f"{appid}{suffix}.ico")
    if os.path.exists(path):
        print(f"✅ Skipping {suffix} image — already exists.")
        continue
    try:
        print(f"Downloading: {url}")
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as resp, open(path, "wb") as out:
            out.write(resp.read())
        print(f"✅ Saved {suffix} image.")
    except Exception as e:
        print(f"⚠️ Failed to download {suffix} image: {e}")

print("✅ All done. Launch Steam to see Minecraft in your Library.")
