# Bazzite GNOME HTPC test build — read this first

This is an experimental source archive, not a verified working release. No
Minecraft, Mutter, Gamescope or controller integration tests were run for this
revision. Only source review, syntax/static analysis and archive inspection
were performed. The older mocked tests are regression helpers, not evidence of
compositor/controller compatibility.

## Install later

1. Extract the **entire** archive in GNOME Desktop Mode, not just the installer.
2. Back up your existing `~/.local/share/minecraft-splitscreen/PrismLauncher` if you have previously installed
   this project. The upstream instance creation module still regenerates instance
   configuration/mod selections; do not use this installer on unrelated instances.
3. Open a terminal in the extracted directory and run:

   ```bash
   bash install-minecraft-splitscreen.sh --debug
   ```

   The required Controllable mod uses CurseForge. Supply your own CurseForge API
   key at the installer's hidden prompt, or set `MSS_CURSEFORGE_API_KEY` in your
   shell. It is used during installation only, not stored or deliberately logged.
   This fork removes the inherited shared-token download/decryption mechanism.

4. Enable Steam integration, choose compatible mods, and add/configure your
   legitimately owned accounts in PrismLauncher. The inherited P1–P4 entries are local
   offline profiles, not authenticated Minecraft licenses or online-server accounts.
   The launcher expects profile names P1, P2, P3 and P4. Per-player account roots
   are created on first launch; after that edit accounts in those roots as needed.
   Prism Launcher normally requires at least one authenticated account with game
   ownership before allowing offline accounts. The supplied offline profiles do
   not bypass that restriction. Open the dedicated launcher explicitly:

   ```bash
   APPIMAGE_EXTRACT_AND_RUN=1 ~/.local/share/minecraft-splitscreen/PrismLauncher/PrismLauncher.AppImage -d ~/.local/share/minecraft-splitscreen/PrismLauncher
   ```

   The dedicated data root is intentionally separate from an existing native or
   Flatpak Prism installation; it does not import or overwrite its accounts or worlds.
   If multiple Steam accounts have userdata directories, set `MSS_STEAM_USER_ID`
   to the intended numeric directory name before running the installer; automatic
   selection deliberately refuses an ambiguous account. Existing shortcuts receive
   a backup next to `shortcuts.vdf` before atomic replacement.
5. Connect two physical controllers and return to **real Steam Gaming Mode**,
   not GNOME Desktop's Steam Big Picture. Initially avoid shaders and extra mods.
6. Launch Minecraft Splitscreen. P1 opens a world to LAN; other players join it.

Development fork: https://github.com/Nailima-AI/MinecraftSplitscreenSteamdeck.
The bundled modules and launcher from this fork are authoritative.
Self-updating is **off by default** so upstream cannot overwrite these changes.
Do not use the old README's upstream one-file download command for this build.

## Preflight and launch overrides

From Desktop Mode, this prints paths/dependency information without starting a game:

```bash
bash ~/.local/share/minecraft-splitscreen/PrismLauncher/minecraftSplitscreen.sh --diagnose
```

`gaming_mode=no` is expected from Desktop Mode. Run this there to check whether
Mutter, Xwayland, dbus-run-session and flock are present. GNOME uses Mutter as a
library, which does **not** guarantee the standalone `mutter` executable is installed
on every Bazzite build. If a dependency is missing, stop and send the diagnostics;
this build does not layer packages automatically.

Steam launch options (before `%command%`):

```text
MSS_COMPOSITOR=mutter MSS_PLAYERS=2 %command%
```

Optional output size override:

```text
MSS_COMPOSITOR=mutter MSS_PLAYERS=2 MSS_RESOLUTION=1920x1080 %command%
```

`MSS_GAME_MODE=1` is available for diagnosis of session detection, but does not
create a parent Wayland session. Do not force it from SSH. `MSS_COMPOSITOR=direct`
is a manual Desktop Mode fallback; it is not a Gamescope split-screen solution.
Controller isolation currently prefers physical Linux joystick devices. Try
disabling Steam Input for this shortcut if inputs are duplicated; real-hardware
validation is required for your controller models. Make sure each controller mod
accepts unfocused input; vanilla's pause-on-focus option is disabled automatically.

## Automatic logs

Every launch writes a private directory under:

```text
~/.local/state/minecraft-splitscreen/run-<UTC timestamp>-<PID>/
```

If you set `XDG_STATE_HOME`, its `minecraft-splitscreen` directory is used instead.

| File | Contents |
| --- | --- |
| events.log | UTC timestamps, session/display routing, controller IDs, layout, process lifecycle, errors with line numbers |
| launcher.log | Launcher stdout/stderr and startup failures |
| compositor.log | Mutter output, rendering/Xwayland errors and compositor failures |
| P1-launcher.log … P4-launcher.log | Each isolated PrismLauncher frontend's output |
| install-…/installer.log | Separate timestamped installer output |

Raw logs are private but may contain credentials printed by upstream tools.
No `set -x` shell tracing or whole-environment/process-command dumps are enabled.
Logs are retained until you remove them; check disk usage periodically.

## Collect a report after testing

Close Minecraft first so logs have finished writing. From a writable directory:

```bash
python3 ~/.local/share/minecraft-splitscreen/PrismLauncher/collect-debug.py
```

Or select a failed run explicitly:

```bash
python3 ~/.local/share/minecraft-splitscreen/PrismLauncher/collect-debug.py --run ~/.local/state/minecraft-splitscreen/run-TIMESTAMP-PID
```

The collector creates `minecraft-splitscreen-debug-<UTC timestamp>.zip` in the
current directory. It includes the selected run, latest install log, available
Minecraft latest/crash logs and minimal system metadata. It never intentionally
includes account JSON, worlds, API-key files, complete
environment variables or full process command lines. Common secret-bearing lines,
emails, IPv4 addresses, UUIDs and JWTs are redacted. Review it before sharing:
player names, chat, paths, IPv6 addresses and server names may remain.

Send that ZIP with player count, controller models, Bazzite version, GPU,
resolution, Steam Input state, what you clicked and the visible failure.

## Known unverified areas

- Nested Mutter/Xwayland must expose a usable DISPLAY and produce a single
  composed output that outer Gamescope displays. The launcher logs both sides of
  the handoff; displaying all quadrants, focus and pointer behavior remain untested.
- Sharing asset/library caches between isolated PrismLauncher roots could expose launcher
  cache races during first downloads. Let one instance finish downloading before
  beginning a full multiplayer trial.
- Physical-controller access and Controllable's SDL filtering vary across devices.
- First-run Java/authentication prompts can delay startup. The default readiness
  timeout is 120 seconds; `MSS_STARTUP_POLLS=600` raises it to 300 seconds.
- The upstream Fabric/CurseForge dependency resolver and Steam shortcut writer
  remain largely inherited. API/version compatibility must be checked during install.
- SIGKILL cannot be trapped; if Steam force-kills the whole process tree, normal
  exit markers can be absent. Relaunch only after previous Minecraft clients close.

- The Prism AppImage is launched with `APPIMAGE_EXTRACT_AND_RUN=1` by default,
  avoiding a hard dependency on FUSE. It still requires compatible host Qt/graphics
  libraries and extraction space. This is not a Flatpak-based setup.
- This archive targets x86_64 HTPCs. Installation downloads Prism, Java (if needed)
  and mods, so it requires internet access. Four inherited 4096 MiB JVM limits can
  total 16 GiB of heap; lower each instance's memory limit for smaller systems.

## Static review changes

- Generic Gamescope detection; no Steam Deck hardware/username requirement.
- Explicit nested handoff and missing-Xwayland/display failure checks.
- Disabled upstream self-updates; preserved existing account/settings files.
- Per-player PrismLauncher data roots, avoiding IPC environment leakage.
- Removed broad frontend/panel killing; scoped game lifetime tracking and launch lock.
- Fixed invalid top-level `local`, empty controller-array output and unquoted paths.
- Error/status logging without secret-bearing command traces; private report collector.
- Steam shutdown refusal, unambiguous user selection, quoted paths and atomic
  shortcut writes with unique backups; missing bundled scripts cannot fetch upstream.
