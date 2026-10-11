# Static review record — debug v0.2

Prepared for Bazzite GNOME HTPC, x86_64, using official Prism Launcher.
Upstream: https://github.com/FlyingEwok/MinecraftSplitscreenSteamdeck
Development fork: https://github.com/Nailima-AI/MinecraftSplitscreenSteamdeck
Local branch: feat/bazzite-gnome-htpc; the published build is on the fork's main branch.

## Checks performed

- Bash syntax parsing (`bash -n`) on every root, module and test shell script.
- Python AST parsing of both Python scripts, without executing them.
- JSON parsing of the bundled offline-profile template.
- `git diff --check` for patch/whitespace problems.
- Case-insensitive source/documentation search for obsolete launcher names/paths.
- Manual review of launcher routing, isolation, account preservation, signals,
  process tracking, Steam shortcuts, AppImage acquisition and diagnostic collection.
- Prism's official CLI documentation checked for `-d`, `-l` and `-a` semantics:
  https://www.prismlauncher.org/wiki/getting-started/command-line-interface/

These parsing checks passed. They do not verify behavior. ShellCheck was not
available in the build environment. No game, installer, diagnostic collector,
Mutter session, controller integration or mocked regression tests were executed
for this revision. Archive integrity is checked separately during packaging.

## Main issues addressed

- Official Prism AppImage and dedicated data root throughout installation,
  shortcut creation, launch, logs and uninstall; no old-launcher fallback.
- Per-player Prism roots prevent single-instance IPC from losing controller and
  nested display environment. Account refresh state is retained after initial copy.
- Timestamped private logs, shell error locations, nested display guard, explicit
  missing-dependency errors, readiness timeout and per-player Java lifecycle events.
- Launch lock, PID-start-time checks for frontends, scoped instance termination,
  removal of broad launcher/panel killing and unqualified `wait`.
- Automatic upstream replacement disabled; bundled scripts required.
- Steam writes require a stopped client and an unambiguous user; quoted paths,
  unique backups, atomic replacement and visible failure diagnostics.
- Empty device arrays no longer create phantom controllers; physical Valve and
  third-party controllers can be assigned together, with readability checks.
- Collector includes only named logs and bounded tails, avoids account/world
  files and uses best-effort secret redaction with an explicit review warning.
- Publishing review rejected the inherited shared-token mechanism. The current
  source removes the encrypted token and every download/decryption path; required
  CurseForge access uses the installer's hidden prompt or MSS_CURSEFORGE_API_KEY.
  Historical upstream commits remain part of the public fork's inherited history.

## What must be verified on the real HTPC

Read TESTING.md before installation. Standalone Mutter availability, nested
Xwayland/display routing, split-screen mod positioning, unfocused controller
input, mixed-device mappings, AppImage host compatibility, legitimate Prism
authentication and inherited mod/version API behavior remain unverified.

Prism/cache concurrency and shutdown of AppImage wrapper descendants also need
real observations. A terminated frontend PID is not proof that every helper has
exited. Do not relaunch while previous clients remain active. Four default heaps
can total 16 GiB; tune memory limits in each instance if needed.
