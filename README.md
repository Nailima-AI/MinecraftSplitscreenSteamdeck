# Minecraft Splitscreen Steam Deck & Linux Installer

> Experimental **Prism Launcher** build for Bazzite GNOME HTPC. Start with
> [TESTING.md](TESTING.md) for installation, known limitations and debug collection.
> No real Minecraft/compositor/controller testing has been performed for this revision.

## AI-generated code disclaimer

Changes introduced in this fork were generated and modified with AI assistance (OpenAI Codex). They received static review and syntax checks, but have not been validated through real Minecraft, compositor or controller testing. Review the code and follow [TESTING.md](TESTING.md) before relying on this experimental build. This notice applies to this fork's changes, not to the original upstream project's authorship.

Development fork: [Nailima-AI/MinecraftSplitscreenSteamdeck](https://github.com/Nailima-AI/MinecraftSplitscreenSteamdeck).
Download or clone the complete repository; the experimental installer requires its bundled modules.
CurseForge-backed mods require your own API key. The installer prompts with hidden
input, or accepts `MSS_CURSEFORGE_API_KEY`; shared encrypted credentials are not bundled.

Simple installer for running **Minecraft splitscreen (1–4 players)** on Steam Deck, Bazzite HTPC and Linux using **PrismLauncher**.

## What This Does
- Installs/updates PrismLauncher in `~/.local/share/minecraft-splitscreen/PrismLauncher`
- Creates 4 splitscreen instances (`latestUpdate-1` to `latestUpdate-4`)
- Installs Fabric and required splitscreen mods
- Lets you choose optional compatible mods
- Lets you add custom Modrinth/CurseForge mods with compatibility checks
- Optionally adds launchers to Steam and desktop
- Detects generic Gamescope sessions instead of requiring Steam Deck hardware
- Uses nested Mutter automatically on Bazzite GNOME HTPC

## Bazzite GNOME HTPC

Install the `bazzite-deck-gnome`/HTPC image so Steam Gaming Mode is available. Run the installer from GNOME Desktop Mode, enable Steam integration, connect all controllers, then launch **Minecraft Splitscreen** from Gaming Mode.

The launcher detects Bazzite's Gamescope session without depending on a Steam Deck product name or the `deck` username. The experimental GNOME backend attempts a nested Mutter compositor at the current output resolution and routes Minecraft to its Xwayland display. It does not install KDE or layer packages. The standalone `mutter` executable and Xwayland must already be available; GNOME's Mutter library alone is insufficient. See TESTING.md for unverified compatibility areas.

Diagnostics:

```sh
~/.local/share/minecraft-splitscreen/PrismLauncher/minecraftSplitscreen.sh --diagnose
```

Optional overrides:

```sh
# Force the Bazzite GNOME backend
MSS_COMPOSITOR=mutter ~/.local/share/minecraft-splitscreen/PrismLauncher/minecraftSplitscreen.sh

# Override output size if Gamescope does not report it correctly
MSS_RESOLUTION=3840x2160 ~/.local/share/minecraft-splitscreen/PrismLauncher/minecraftSplitscreen.sh

# Bypass nesting for troubleshooting in Desktop Mode
MSS_COMPOSITOR=direct ~/.local/share/minecraft-splitscreen/PrismLauncher/minecraftSplitscreen.sh
```

## Core Mods (Required)
- [Controllable](https://www.curseforge.com/minecraft/mc-mods/controllable)
- [Splitscreen Support](https://modrinth.com/mod/splitscreen)

## Optional Mods
- [Better Name Visibility](https://modrinth.com/mod/better-name-visibility)
- [Full Brightness Toggle](https://modrinth.com/mod/full-brightness-toggle)
- [In-Game Account Switcher](https://modrinth.com/mod/in-game-account-switcher)
- [Just Zoom](https://modrinth.com/mod/just-zoom)
- [Mod Menu](https://modrinth.com/mod/modmenu)
- [Old Combat Mod](https://modrinth.com/mod/old-combat-mod)
- [Reese's Sodium Options](https://modrinth.com/mod/reeses-sodium-options)
- [Sodium](https://modrinth.com/mod/sodium)
- [Sodium Dynamic Lights](https://modrinth.com/mod/sodium-dynamic-lights)
- [Sodium Extra](https://modrinth.com/mod/sodium-extra)
- [Sodium Extras](https://modrinth.com/mod/sodium-extras)

## Requirements
- Linux (Steam Deck or desktop Linux)
- Internet connection for install/update
- `bash`, `curl` or `wget`, and `jq`
- Python 3 only if you want automatic Steam shortcut integration

No manual Java setup is required. The installer detects and installs the needed Java version automatically.

## Install
```sh
# Run from the complete extracted archive, not the upstream installer.
bash install-minecraft-splitscreen.sh --debug
```

### Debug Mode
Use this if you want verbose logs:
```sh
./install-minecraft-splitscreen.sh --debug
```

## How Installation Works
1. Downloads/updates PrismLauncher
2. Lets you pick a compatible Minecraft version
3. Detects/installs the correct Java version
4. Checks mod compatibility and lets you choose optional mods
5. Optionally accepts custom mods (URL/ID), validates compatibility, and warns about risk
6. Creates/updates 4 manual PrismLauncher instances with Fabric
7. Installs mods and dependencies
8. Optionally adds Steam + desktop shortcuts

### Custom Mod Input Formats
- Easiest CurseForge format: paste only the numeric project ID (example: `422301`)
- Easiest Modrinth format: paste mod URL or slug (example: `https://modrinth.com/mod/sodium` or `sodium`)
- Also supported: `mr:<slug-or-id>` and `cf:<id>`

Quick examples:
- `422301`
- `sodium`
- `https://modrinth.com/mod/sodium`
- `cf:422301`

Custom mods are validated against Fabric and your exact selected Minecraft version. If incompatible, the installer lets you skip it or stop. If the mod supports Fabric but not your selected Minecraft version, it also offers switching to a supported version.

Minecraft version selection is list-based (no manual custom version entry).  
If a custom mod is incompatible, you can choose to switch versions and the installer will show only versions that support both core mods and that requested custom mod.

## Launching
After install, run:
```sh
~/.local/share/minecraft-splitscreen/PrismLauncher/minecraftSplitscreen.sh
```

You can also launch from Steam or desktop if you enabled those integrations.

## Install Locations
- Main directory: `~/.local/share/minecraft-splitscreen/PrismLauncher/`
- Splitscreen launcher: `~/.local/share/minecraft-splitscreen/PrismLauncher/minecraftSplitscreen.sh`
- Instances: `~/.local/share/minecraft-splitscreen/PrismLauncher/instances/`

## Updating
Re-run the installer anytime:
```sh
./install-minecraft-splitscreen.sh
```

The installer updates instance configs and mods for the version you select, while preserving existing instance/user data where possible.

## TODO
- Explore an optional "fast launch mode" for Steam Deck that reduces startup delays where possible while keeping the current reliable default behavior unchanged.
- Validate additional non-Bazzite GNOME distributions and unusual multi-monitor layouts.

## Uninstall
```sh
bash uninstall-minecraft-splitscreen.sh --keep-data
```

Optional uninstall flags:
- `--yes`
- `--dry-run`
- `--keep-data`

## Troubleshooting
- Connect controllers before launching.
- If controller assignment seems wrong, close all instances and relaunch.
- Steam Deck users can optionally use [Steam-Deck.Auto-Disable-Steam-Controller](https://github.com/scawp/Steam-Deck.Auto-Disable-Steam-Controller) as a fallback for edge-case controller conflicts.
- Custom mods are best-effort and untested in this setup; incompatible or conflicting mods can break splitscreen behavior.

## Credits
- Inspired by [ArnoldSmith86/minecraft-splitscreen](https://github.com/ArnoldSmith86/minecraft-splitscreen)
- Built and maintained by [FlyingEwok](https://github.com/FlyingEwok) and contributors
- Uses [PrismLauncher](https://github.com/PrismLauncher/PrismLauncher)
- Uses [install-jdk-on-steam-deck](https://github.com/FlyingEwok/install-jdk-on-steam-deck) for Java setup on Steam Deck/Linux
