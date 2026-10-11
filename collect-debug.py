#!/usr/bin/env python3
"""Collect bounded, allowlisted diagnostics; never include account/config secrets."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import platform
import re
import shutil
import zipfile

MAX_BYTES = 4 * 1024 * 1024
SENSITIVE = re.compile(
    r"access.?token|refresh.?token|client.?token|id.?token|authorization|"
    r"x-api-key|api.?key|password|passwd|--session|session.?id|"
    r"minecraftservices\.com/authentication|login\.live\.com|device.?code|"
    r"user.?code|microsoft\.com/link", re.I
)


def redact(text, home):
    # Fail closed at the line level for recognizable authentication output.
    lines = ["[REDACTED: sensitive line]" if SENSITIVE.search(line) else line
             for line in text.splitlines()]
    text = "\n".join(lines).replace(str(home), "$HOME")
    text = re.sub(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "[JWT]", text)
    text = re.sub(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "[IP]", text)
    text = re.sub(r"\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b", "[UUID]", text, flags=re.I)
    text = re.sub(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", "[EMAIL]", text)
    return text + "\n"


def read_tail(path):
    if path.is_symlink() or not path.is_file():
        return None
    with path.open("rb") as stream:
        size = path.stat().st_size
        if size > MAX_BYTES:
            stream.seek(size - MAX_BYTES)
            stream.readline()  # Discard partial line.
        data = stream.read(MAX_BYTES)
    prefix = "[Earlier output omitted: file exceeds 4 MiB]\n" if size > MAX_BYTES else ""
    return prefix + data.decode("utf-8", errors="replace")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, help="Specific run log directory; defaults to newest")
    parser.add_argument("--output", type=Path, help="Destination ZIP; must not already exist")
    args = parser.parse_args()
    home = Path.home()
    state = Path(os.environ.get("XDG_STATE_HOME", str(home / ".local/state"))) / "minecraft-splitscreen"
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = args.output or Path.cwd() / f"minecraft-splitscreen-debug-{stamp}.zip"
    if output.exists():
        parser.error("Output already exists; choose another name")
    runs = sorted((p for p in state.glob("run-*") if p.is_dir() and not p.is_symlink()),
                  key=lambda p: p.stat().st_mtime, reverse=True)
    run = args.run or (runs[0] if runs else None)
    if run is not None and (not run.is_dir() or run.is_symlink() or run.resolve().parent != state.resolve()):
        parser.error("Run directory must be a direct, non-symlink child of the log directory")
    files = []
    if run:
        names = ("events.log", "launcher.log", "compositor.log",
                 "P1-launcher.log", "P2-launcher.log", "P3-launcher.log", "P4-launcher.log")
        files.extend((run / name, "run/" + name) for name in names)
    installs = sorted((p for p in state.glob("install-*") if p.is_dir() and not p.is_symlink()),
                      key=lambda p: p.stat().st_mtime, reverse=True)
    if installs:
        files.append((installs[0] / "installer.log", "install/installer.log"))
    game_root = home / ".local/share/minecraft-splitscreen/PrismLauncher/instances"
    for player in range(1, 5):
        game = game_root / f"latestUpdate-{player}" / ".minecraft"
        files.append((game / "logs/latest.log", f"P{player}/minecraft-latest.log"))
        if (game / "crash-reports").is_dir() and not (game / "crash-reports").is_symlink():
            crashes = sorted((game / "crash-reports").glob("*.txt"),
                             key=lambda p: p.stat().st_mtime, reverse=True)
            if crashes:
                files.append((crashes[0], f"P{player}/latest-crash.txt"))
    dependencies = {name: shutil.which(name) for name in
                    ("mutter", "Xwayland", "dbus-run-session", "xdpyinfo", "flock", "java", "gamescope")}
    system = {
        "created_utc": stamp, "kernel": platform.release(), "architecture": platform.machine(),
        "selected_run": run.name if run else None, "dependencies": dependencies,
        "collector_session": {k: os.environ.get(k, "") for k in
                              ("XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "XDG_SESSION_TYPE",
                               "DISPLAY", "WAYLAND_DISPLAY")},
        "note": "Collector session may differ from the session used to launch Minecraft.",
        "included": [], "unavailable": [],
    }
    for source, name in ((Path("/etc/os-release"), "system/os-release.txt"),
                         (Path("/proc/meminfo"), "system/meminfo.txt")):
        files.append((source, name))
    # Exclusive creation and restrictive permissions; no world-readable raw logs.
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as stream, zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
        for path, name in files:
            try:
                text = read_tail(path)
            except (OSError, ValueError) as exc:
                system["unavailable"].append({"file": name, "error": type(exc).__name__})
                continue
            if text is None:
                continue
            archive.writestr(name, redact(text, home))
            system["included"].append(name)
        archive.writestr("system/summary.json", redact(json.dumps(system, indent=2), home))
        archive.writestr("READ-ME-FIRST.txt",
                         "Inspect this archive before sharing. Automated redaction is best effort.\n"
                         "Player names, chat, server names and paths can remain. Account files,\n"
                         "full process command lines, saves and token.enc are intentionally excluded.\n"
                         "Game logs may be from an older session if a player never reached startup.\n")
    print(f"Created {output.resolve()}")
    print("Review contents before sharing; send this ZIP with the steps that reproduced the problem.")


if __name__ == "__main__":
    main()
