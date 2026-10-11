#!/bin/bash

set +e
set -E
umask 077

# =============================
# Minecraft Splitscreen Launcher for Steam Deck, Bazzite HTPC & Linux
# =============================
# This script launches 1–4 Minecraft instances in splitscreen mode.
# In Steam Gaming Mode, it launches an available nested desktop compositor for clean splitscreen.
# On desktop mode, it launches Minecraft instances directly.
# Handles controller detection, isolated Prism roots and nested session logging.
#
# HOW IT WORKS:
# 1. If in Steam Gaming Mode, launches nested Plasma or Mutter (if not already inside).
# 2. Sets up an autostart .desktop file to re-invoke itself inside the nested session.
# 3. Detects how many controllers are connected (1–4, with Steam Input quirks handled).
# 4. For each player, writes the correct splitscreen mod config and launches a Minecraft instance.
# 5. Tracks only the Java instances launched by this session.
# 6. Logs out of the nested session when done.
#
# NOTE: This script is robust and heavily commented for clarity and future maintainers!
# The main script file should be named minecraftSplitscreen.sh for clarity and version-agnostic usage.

# Set a temporary directory for intermediate files (used for wrappers, etc)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MSS_LOG_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/minecraft-splitscreen"
MSS_LOG_DIR="${MSS_LOG_DIR:-$MSS_LOG_ROOT/run-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p -- "$MSS_LOG_DIR" || exit 1
export MSS_LOG_DIR
LAUNCH_DEBUG_LOG="$MSS_LOG_DIR/events.log"
exec > >(tee -a "$MSS_LOG_DIR/launcher.log") 2>&1
logEvent() {
    printf '%s pid=%s level=%s event=%s\n' "$(date -u +%FT%TZ)" "$BASHPID" "$1" "$2" >> "$LAUNCH_DEBUG_LOG"
}
trap 'logEvent ERROR "shell_error source=${BASH_SOURCE[0]##*/} line=$LINENO rc=$?"' ERR
trap 'logEvent INFO "early_exit rc=$?"' EXIT
logEvent INFO "startup stage=${1:-outer} session=${XDG_SESSION_DESKTOP:-unset} desktop=${XDG_CURRENT_DESKTOP:-unset} display=${DISPLAY:-unset} wayland=${WAYLAND_DISPLAY:-unset}"
logEvent INFO 'build=prism-bazzite-gnome-debug-v0.2'
echo "[Info] Diagnostic logs: $MSS_LOG_DIR"
declare -a MSS_GAME_PIDS=()
declare -a MSS_GAME_INSTANCES=()
declare -a MSS_FRONTEND_PIDS=()
declare -a MSS_FRONTEND_START_TIMES=()
MSS_REPO_SLUG="${MSS_REPO_SLUG:-Nailima-AI/MinecraftSplitscreenSteamdeck}"
MSS_COMPOSITOR="${MSS_COMPOSITOR:-auto}"
export APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}"

# =============================
# Function: detectLauncher
# =============================
# Detects PrismLauncher launcher for splitscreen gameplay.
# Returns launcher paths and executable info.
detectLauncher() {
    # Check if PrismLauncher is available.
    if [ -f "$HOME/.local/share/minecraft-splitscreen/PrismLauncher/PrismLauncher.AppImage" ] && [ -x "$HOME/.local/share/minecraft-splitscreen/PrismLauncher/PrismLauncher.AppImage" ]; then
        export LAUNCHER_DIR="$HOME/.local/share/minecraft-splitscreen/PrismLauncher"
        export LAUNCHER_EXEC="$HOME/.local/share/minecraft-splitscreen/PrismLauncher/PrismLauncher.AppImage"
        export LAUNCHER_NAME="PrismLauncher"
        return 0
    fi
    
    echo "[Error] PrismLauncher not found at $HOME/.local/share/minecraft-splitscreen/PrismLauncher/" >&2
    echo "[Error] Please run the Minecraft Splitscreen installer to set up PrismLauncher" >&2
    return 1
}

# Detect and set launcher variables at startup
if [ "${1:-}" = --diagnose ]; then
    LAUNCHER_DIR="$HOME/.local/share/minecraft-splitscreen/PrismLauncher"
    LAUNCHER_NAME=PrismLauncher
elif ! detectLauncher; then
    echo "[Error] Cannot continue without a compatible Minecraft launcher" >&2
    exit 1
fi

echo "[Info] Using $LAUNCHER_NAME for splitscreen gameplay"

# =============================
# Function: selfUpdate
# =============================
# Checks if this script is the latest version from GitHub. If not, downloads and replaces itself.
selfUpdate() {
    local repo_url="https://raw.githubusercontent.com/${MSS_REPO_SLUG}/main/minecraftSplitscreen.sh"
    local tmpfile
    tmpfile=$(mktemp)
    local script_path
    script_path="$(readlink -f "$0")"
    # Download the latest version
    if ! curl -fsSL "$repo_url" -o "$tmpfile"; then
        echo "[Self-Update] Failed to check for updates." >&2
        rm -f "$tmpfile"
        return
    fi
    # Compare files byte-for-byte
    if ! cmp -s "$tmpfile" "$script_path"; then
        # --- Terminal Detection and Relaunch Logic ---
        # If not running in an interactive shell (no $PS1), not launched by a terminal program, and not attached to a tty,
        # then we are likely running from a GUI (e.g., .desktop launcher) and cannot prompt the user for input.
        if [ -z "$PS1" ] && [ -z "$TERM_PROGRAM" ] && ! tty -s; then
            # Non-interactive launch (desktop shortcut/autostart/Game Mode path):
            # do not block or abort gameplay flow for an update prompt.
            echo "[Self-Update] Update available. Skipping prompt in non-interactive mode."
            rm -f "$tmpfile"
            return
        fi
        # --- Interactive Update Prompt ---
        # If we are running in a terminal, prompt the user for update confirmation.
        echo "[Self-Update] A new version is available. Update now? [y/N]"
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            echo "[Self-Update] Updating..."
            cp "$tmpfile" "$script_path"
            chmod +x "$script_path"
            rm -f "$tmpfile"
            echo "[Self-Update] Update complete. Restarting..."
            exec "$script_path" "$@"
        else
            echo "[Self-Update] Update skipped by user."
            rm -f "$tmpfile"
        fi
    else
        rm -f "$tmpfile"
        echo "[Self-Update] Already up to date."
    fi
}

# Call selfUpdate at the very start of the script, except in the nested
# autostart handoff path where we want deterministic immediate launch.
# Local test builds must never be replaced by upstream at launch. Opt in only
# after a published fork URL has been configured explicitly.
if [ "${MSS_ENABLE_SELF_UPDATE:-0}" = "1" ] && [ "${MSS_DISABLE_SELF_UPDATE:-0}" != "1" ] && \
   [ "${1:-}" != "launchFromPlasma" ] && \
   [ "${1:-}" != "launchFromMutter" ] && \
   [ "${1:-}" != "--diagnose" ]; then
    if [ "$MSS_REPO_SLUG" = FlyingEwok/MinecraftSplitscreenSteamdeck ]; then
        echo '[Warning] Self-update refused: upstream would replace this Prism build.'
    else
        selfUpdate
    fi
fi

# Return the outer display size used by the nested compositor. Bazzite's
# Gamescope session normally exposes this through xdpyinfo; the environment
# override is useful on unusual HTPC displays and for diagnostics.
getOutputResolution() {
    local resolution="${MSS_RESOLUTION:-}"
    if [ -z "$resolution" ] && command -v xdpyinfo >/dev/null 2>&1; then
        resolution="$(xdpyinfo 2>/dev/null | awk '/dimensions/{print $2; exit}')"
    fi
    if ! [[ "$resolution" =~ ^[0-9]+x[0-9]+$ ]]; then
        resolution="1920x1080"
    fi
    printf '%s\n' "$resolution"
}

# =============================
# Function: nestedPlasma
# =============================
# Launches a nested KDE Plasma Wayland session and sets up Minecraft autostart.
# Needed so Minecraft can run in a clean, isolated desktop environment (avoiding SteamOS overlays, etc).
# The autostart .desktop file ensures Minecraft launches automatically inside the nested session.
nestedPlasma() {
    command -v dbus-run-session >/dev/null && command -v startplasma-wayland >/dev/null || return 1
    target="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/minecraft-plasma.XXXXXX")" || return 1
    # Unset variables that may interfere with launching a nested session
    unset LD_PRELOAD XDG_DESKTOP_PORTAL_DIR XDG_SEAT_PATH XDG_SESSION_PATH
    # Get current screen resolution (e.g., 1280x800)
    RES="$(getOutputResolution)"
    # Create a wrapper for kwin_wayland with the correct resolution
    cat <<EOF > $target/kwin_wayland_wrapper
#!/bin/bash
/usr/bin/kwin_wayland_wrapper --width ${RES%x*} --height ${RES#*x} --no-lockscreen \$@
EOF
    chmod +x $target/kwin_wayland_wrapper
    export PATH=$target:$PATH
    # Write an autostart .desktop file that will re-invoke this script with a special argument
    SCRIPT_PATH="$(readlink -f "$0")"
    mkdir -p ~/.config/autostart
    if [ -e "$HOME/.config/autostart/minecraft-launch.desktop" ]; then
        echo '[Error] A minecraft-launch.desktop autostart already exists; refusing to replace it.' >&2
        return 1
    fi
    MSS_CREATED_AUTOSTART=1
    cat <<EOF > ~/.config/autostart/minecraft-launch.desktop
[Desktop Entry]
Name=Minecraft Split Launch
Exec=$SCRIPT_PATH launchFromPlasma
Type=Application
X-KDE-AutostartScript=true
EOF
    # Start nested Plasma session (never returns)
    logEvent INFO "compositor_start backend=plasma resolution=$RES"
    dbus-run-session startplasma-wayland
    local rc=$?
    logEvent INFO "compositor_exit backend=plasma rc=$rc"
    rm -f -- "$target/kwin_wayland_wrapper"
    rmdir -- "$target"
    return "$rc"
}

# Launch a nested Mutter compositor using components already present in the
# Bazzite GNOME image. Mutter's command mode starts the launcher inside the
# nested session, so its Wayland/Xwayland display variables are inherited by
# every Minecraft instance.
nestedMutter() {
    local resolution script_path
    resolution="$(getOutputResolution)"
    script_path="$(readlink -f "$0")"

    if ! command -v mutter >/dev/null 2>&1; then
        logEvent ERROR 'missing_dependency command=mutter'
        echo "[Error] Mutter is unavailable; cannot create the GNOME nested session." >&2
        echo "[Error] Set MSS_COMPOSITOR=direct to use Desktop Mode without nesting." >&2
        return 1
    fi

    for required in dbus-run-session Xwayland; do
        if ! command -v "$required" >/dev/null 2>&1; then
            logEvent ERROR "missing_dependency command=$required"
            echo "[Error] Required command '$required' is missing; see TESTING.md." >&2
            return 1
        fi
    done
    if [ -z "${WAYLAND_DISPLAY:-}" ]; then
        logEvent ERROR 'missing_parent_wayland_display'
        echo '[Error] No parent Wayland display. Launch from real Gaming Mode, not an SSH terminal.' >&2
        return 1
    fi

    unset LD_PRELOAD XDG_DESKTOP_PORTAL_DIR XDG_SEAT_PATH XDG_SESSION_PATH
    export MUTTER_DEBUG_DUMMY_MODE_SPECS="$resolution"
    export MUTTER_DEBUG_NUM_DUMMY_MONITORS=1 MUTTER_DEBUG_DUMMY_MONITOR_SCALES=1
    export MSS_GAME_MODE=1 MSS_ENABLE_SELF_UPDATE=0
    export MSS_PARENT_DISPLAY="${DISPLAY:-}"
    export XDG_CURRENT_DESKTOP=MSS-Mutter
    echo "[Info] Starting nested Mutter session at $resolution for Bazzite GNOME..."

    logEvent INFO "compositor_start backend=mutter resolution=$resolution"
    dbus-run-session -- mutter --wayland --nested -- \
        "$script_path" launchFromMutter >> "$MSS_LOG_DIR/compositor.log" 2>&1
    local rc=$?
    logEvent INFO "compositor_exit backend=mutter rc=$rc"
    if [ "$rc" -ne 0 ]; then
        echo "[Error] Mutter exited with status $rc. See $MSS_LOG_DIR/compositor.log"
    fi
    return "$rc"
}

# =============================
# Function: launchGame
# =============================
# Launches a single Minecraft instance using the detected launcher, with KDE inhibition to prevent
# the system from sleeping, activating the screensaver, or changing color profiles.
# Arguments:
#   $1 = Launcher instance name (e.g., latestUpdate-1)
#   $2 = Player name (e.g., P1)
launchGame() {
    local instance_name="$1"
    local account_name="$2"
    local joystick_device="${3:-}"
    local startup_polls="${MSS_STARTUP_POLLS:-240}"
    if ! [[ "$startup_polls" =~ ^[1-9][0-9]{0,4}$ ]]; then
        logEvent ERROR 'invalid_startup_polls use_positive_integer_up_to_99999'
        return 1
    fi

    echo "[Info] Launching $LAUNCHER_NAME instance '$instance_name' with account '$account_name'..."
    if [ -n "$joystick_device" ]; then
        echo "[Info]   -> Restricting instance input to joystick device: $joystick_device"
    fi

    local -a launch_cmd
    # PrismLauncher forwards requests to an existing process for the same data root.
    # Separate roots keep SDL environment and nested DISPLAY from leaking into
    # an unrelated already-open launcher. Share only game/cache directories.
    local profile_dir="$LAUNCHER_DIR/splitscreen-profiles/$account_name"
    mkdir -p -- "$profile_dir/instances" || return 1
    local cache
    for cache in assets libraries meta icons; do
        mkdir -p -- "$LAUNCHER_DIR/$cache" || return 1
        if [ ! -e "$profile_dir/$cache" ]; then
            ln -s -- "$LAUNCHER_DIR/$cache" "$profile_dir/$cache" || return 1
        fi
    done
    if [ ! -e "$profile_dir/instances/$instance_name" ]; then
        ln -s -- "$LAUNCHER_DIR/instances/$instance_name" "$profile_dir/instances/$instance_name" || return 1
    fi
    cp -- "$LAUNCHER_DIR/prismlauncher.cfg" "$profile_dir/prismlauncher.cfg" || return 1
    if [ ! -f "$profile_dir/accounts.json" ]; then
        cp -- "$LAUNCHER_DIR/accounts.json" "$profile_dir/accounts.json" || return 1
    fi
    launch_cmd=("$LAUNCHER_EXEC" -d "$profile_dir" -l "$instance_name" -a "$account_name")
    logEvent INFO "player_launch instance=$instance_name account=$account_name device=${joystick_device:-none} profile=$profile_dir"

    # SDL hint used by Controllable's bundled SDL backend. This constrains each process
    # to a single joystick path to reduce cross-instance controller collisions.
    local -a launch_env
    launch_env=(env)
    if [ -n "$joystick_device" ]; then
        launch_env+=("SDL_JOYSTICK_DEVICE=$joystick_device")
    fi
    # Steam can inject a very large SDL_GAMECONTROLLER_IGNORE_DEVICES blacklist that may
    # include perfectly valid controllers. Clear it for launched instances.
    launch_env+=("SDL_GAMECONTROLLER_IGNORE_DEVICES=")
    # Prefer physical controllers over Steam virtual pads in Controllable.
    launch_env+=("SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=0")
    # Force SDL to use Linux joystick devices instead of HIDAPI so SDL_JOYSTICK_DEVICE
    # pinning is applied per instance.
    launch_env+=("SDL_JOYSTICK_HIDAPI=0")
    # SDL expects SDL_LINUX_JOYSTICK_CLASSIC (not SDL_JOYSTICK_LINUX_CLASSIC).
    # This is required so SDL_JOYSTICK_DEVICE pinning is honored on Linux.
    launch_env+=("SDL_LINUX_JOYSTICK_CLASSIC=1")

    mkdir -p "$(dirname "$LAUNCH_DEBUG_LOG")"
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching $instance_name ($account_name)"
        echo "  SDL_JOYSTICK_DEVICE=${joystick_device:-<unset>}"
        echo "  SDL_GAMECONTROLLER_IGNORE_DEVICES=<cleared>"
        echo "  SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=0"
        echo "  SDL_JOYSTICK_HIDAPI=0"
        echo "  SDL_LINUX_JOYSTICK_CLASSIC=1"
        echo "  XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-<unset>}"
        echo "  XDG_SESSION_DESKTOP=${XDG_SESSION_DESKTOP:-<unset>}"
    } >> "$LAUNCH_DEBUG_LOG"

    # Only use kde-inhibit inside KDE/Plasma sessions.
    # On GNOME and other desktops it can exist but fail over DBus.
    if command -v kde-inhibit >/dev/null 2>&1 && \
       [[ "${XDG_CURRENT_DESKTOP:-}" =~ KDE|PLASMA ]] ; then
        (
            kde-inhibit --power --screenSaver --colorCorrect --notifications \
                "${launch_env[@]}" "${launch_cmd[@]}"
        ) >> "$MSS_LOG_DIR/$account_name-launcher.log" 2>&1 &
    else
        # On GNOME/other desktops, launch directly to avoid DBus inhibit edge cases.
        "${launch_env[@]}" "${launch_cmd[@]}" >> "$MSS_LOG_DIR/$account_name-launcher.log" 2>&1 &
    fi
    local frontend_pid=$! game_pid=""
    MSS_FRONTEND_PIDS+=("$frontend_pid")
    MSS_FRONTEND_START_TIMES+=("$(processStartTime "$frontend_pid")")
    logEvent INFO "frontend_started player=$account_name pid=$frontend_pid"
    # Wait for this specific instance's Java process to appear so the next
    # player's pre-launch frontend prune won't kill this launch too early.
    local launch_started=0
    local _i
    for ((_i=1; _i<=startup_polls; _i++)); do
        game_pid="$(findGamePid "$instance_name")"
        if [ -n "$game_pid" ]; then
            launch_started=1
            MSS_GAME_PIDS+=("$game_pid")
            MSS_GAME_INSTANCES+=("$instance_name")
            logEvent INFO "java_ready player=$account_name pid=$game_pid polls=$_i"
            break
        fi
        if ! kill -0 "$frontend_pid" 2>/dev/null; then
            wait "$frontend_pid"
            local frontend_rc=$?
            logEvent ERROR "frontend_exit_before_java player=$account_name rc=$frontend_rc"
            return 1
        fi
        sleep 0.5
    done
    if [ "$launch_started" -eq 0 ]; then
        {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Warning: Java process for ${instance_name} not detected within $startup_polls half-second polls"
        } >> "$LAUNCH_DEBUG_LOG"
        logEvent ERROR "java_startup_timeout player=$account_name"
        return 1
    fi
    return 0
}

# Never log full Java command lines: they may contain authentication tokens.
findGamePid() {
    local instance="$1" pid args
    while read -r pid; do
        [ -r "/proc/$pid/cmdline" ] || continue
        args="$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null)"
        if [[ "$args" == *"/instances/$instance/"* ]]; then
            printf '%s\n' "$pid"
            return 0
        fi
    done < <(pgrep -u "$(id -u)" -x java 2>/dev/null)
    return 0
}

processStartTime() {
    local pid="$1" stat
    local -a fields
    [ -r "/proc/$pid/stat" ] || return 0
    stat="$(<"/proc/$pid/stat")"
    # Remove pid and parenthesized comm (which can contain spaces).
    read -r -a fields <<< "${stat##*) }"
    printf '%s\n' "${fields[19]:-}"
}

stopTrackedFrontends() {
    local index pid started
    for index in "${!MSS_FRONTEND_PIDS[@]}"; do
        pid="${MSS_FRONTEND_PIDS[$index]}"
        started="${MSS_FRONTEND_START_TIMES[$index]}"
        if [ -n "$started" ] && [ "$(processStartTime "$pid")" = "$started" ]; then
            logEvent INFO "frontend_stop pid=$pid"
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
}

waitForGames() {
    local index pid instance live
    while :; do
        live=0
        for index in "${!MSS_GAME_PIDS[@]}"; do
            pid="${MSS_GAME_PIDS[$index]}"
            [ -n "$pid" ] || continue
            instance="${MSS_GAME_INSTANCES[$index]}"
            if [ "$(findGamePid "$instance")" = "$pid" ]; then
                live=1
            else
                logEvent INFO "java_exited instance=$instance pid=$pid"
                MSS_GAME_PIDS[$index]=""
            fi
        done
        [ "$live" = 1 ] || break
        sleep 2
    done
    # Only wait for tracked frontends, never an unqualified wait (which would
    # include the long-lived log tee subprocess and hang indefinitely).
    stopTrackedFrontends
    logEvent INFO games_finished
}

# Kill PrismLauncher frontend wrapper processes without touching running Java game processes.
pruneLauncherFrontends() {
    # Kept as a compatibility shim. Isolated per-player data roots make broad
    # process pruning unnecessary; never kill unrelated PrismLauncher processes.
    logEvent INFO "frontend_prune_disabled reason=${1:-manual}"
}

# =============================
# Function: getControllerDevices
# =============================
# Builds an ordered list of joystick devices to map to players. When Steam is running
# and duplicate joystick nodes appear, physical nodes are preferred over virtual pads.
getControllerDevices() {
    local -a js_devices
    local -a external_devices
    local -a deck_devices
    local -a steam_virtual_devices
    local js
    local vendor
    local product
    local base
    local id_dir

    mapfile -t js_devices < <(ls /dev/input/js* 2>/dev/null | sort -V)

    for js in "${js_devices[@]}"; do
        base="$(basename "$js")"
        id_dir="/sys/class/input/$base/device/id"
        vendor="$(cat "$id_dir/vendor" 2>/dev/null || true)"
        product="$(cat "$id_dir/product" 2>/dev/null || true)"
        logEvent INFO "controller_detected node=$js vendor=$vendor product=$product readable=$([ -r "$js" ] && echo yes || echo no)"
        # Steam virtual pads are 28de:11ff and often appear in duplicate.
        if [ "$vendor" = "28de" ] && [ "$product" = "11ff" ]; then
            steam_virtual_devices+=("$js")
        # On Steam Deck, vendor 28de (non-11ff) is Deck/Valve-origin input.
        elif [ "$vendor" = "28de" ]; then
            deck_devices+=("$js")
        # Prefer third-party external controllers whenever present.
        else
            external_devices+=("$js")
        fi
    done

    if [ "$(( ${#external_devices[@]} + ${#deck_devices[@]} ))" -gt 0 ]; then
        # Include Valve-origin physical controllers alongside third-party pads.
        printf '%s\n' "${external_devices[@]}" "${deck_devices[@]}"
    elif [ "${#steam_virtual_devices[@]}" -gt 0 ]; then
        # Only expose one virtual pad node to avoid duplicate assignment.
        printf '%s\n' "${steam_virtual_devices[0]}"
    else
        if [ "${#js_devices[@]}" -gt 0 ]; then
            printf '%s\n' "${js_devices[@]}"
        fi
    fi
}

# Upsert a key/value in a PrismLauncher instance.cfg file.
setInstanceCfgValue() {
    local cfg_path="$1"
    local key="$2"
    local value="$3"
    local tmp_file

    [ -f "$cfg_path" ] || return 1

    if grep -q "^${key}=" "$cfg_path"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$cfg_path"
    else
        printf '%s=%s\n' "$key" "$value" >> "$cfg_path"
    fi

    # Verify write; if it did not stick, use a full-file rewrite fallback.
    if grep -Fqx "${key}=${value}" "$cfg_path"; then
        return 0
    fi

    tmp_file="$(mktemp "${cfg_path}.XXXXXX")" || return 1
    awk -F= -v k="$key" -v v="$value" '
        BEGIN { updated=0 }
        $1 == k { print k "=" v; updated=1; next }
        { print }
        END { if (!updated) print k "=" v }
    ' "$cfg_path" > "$tmp_file"
    mv "$tmp_file" "$cfg_path"

    grep -Fqx "${key}=${value}" "$cfg_path"
}

# Configure per-instance wrapper command so controller pinning is applied at the
# actual game process level (instead of only the launcher process environment).
configureInstanceControllerWrapper() {
    local instance_name="$1"
    local joystick_device="${2:-}"
    local cfg_path="$LAUNCHER_DIR/instances/${instance_name}/instance.cfg"
    local wrapper_cmd=""

    [ -f "$cfg_path" ] || return 1

    if [ -n "$joystick_device" ]; then
        wrapper_cmd="env SDL_JOYSTICK_DEVICE=${joystick_device} SDL_GAMECONTROLLER_IGNORE_DEVICES= SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=0 SDL_JOYSTICK_HIDAPI=0 SDL_LINUX_JOYSTICK_CLASSIC=1"
        setInstanceCfgValue "$cfg_path" "OverrideCommands" "true" || return 1
        setInstanceCfgValue "$cfg_path" "WrapperCommand" "$wrapper_cmd" || return 1
    else
        # No pinning target for this instance; clear wrapper override.
        setInstanceCfgValue "$cfg_path" "OverrideCommands" "false" || return 1
        setInstanceCfgValue "$cfg_path" "WrapperCommand" "" || return 1
    fi

    # Log what ended up in the config so we can diagnose any launcher-side override.
    mkdir -p "$(dirname "$LAUNCH_DEBUG_LOG")"
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Wrapper config for ${instance_name}"
        echo "  $(grep -m1 '^OverrideCommands=' "$cfg_path" || echo 'OverrideCommands=<missing>')"
        echo "  $(grep -m1 '^WrapperCommand=' "$cfg_path" || echo 'WrapperCommand=<missing>')"
    } >> "$LAUNCH_DEBUG_LOG"
}

# Controllable persists manually selected controllers per instance. If this file
# is stale (e.g., both instances saved as Steam Deck), it can override launch-time
# device filtering and cause every instance to grab the same controller.
clearControllableSelection() {
    local instance_name="$1"
    local selected_file="$LAUNCHER_DIR/instances/${instance_name}/.minecraft/config/controllable/selected_controllers.json"
    rm -f "$selected_file"
}

# =============================
# Function: hidePanels
# =============================
# Kills all plasmashell processes to remove KDE panels and widgets. This is a brute-force workaround
# that works even in nested Plasma Wayland sessions, where scripting APIs may not work.
hidePanels() {
    logEvent INFO panel_manipulation_disabled
}

restorePanels() {
    return 0
}

# =============================
# Function: getControllerCount
# =============================
# Detects the number of controllers (1–4) by counting /dev/input/js* devices.
# Steam Input (when Steam is running) creates duplicate devices, so we halve the count (rounding up).
# Ensures at least 1 and at most 4 controllers are reported.
# Logic:
#   - Counts all /dev/input/js* devices (joysticks/gamepads recognized by the system)
#   - Checks if the main Steam client is running (native or Flatpak)
#   - Only halves the count if the main Steam client is running (not just helpers)
#   - Returns a value between 1 and 4 (inclusive)
getControllerCount() {
    local count
    local steam_running=0
    # Count all joystick/gamepad devices
    count=$(ls /dev/input/js* 2>/dev/null | wc -l)
    # Only halve if the main Steam client is running (native or Flatpak)
    #   - pgrep -x steam: native Steam client
    #   - pgrep -f '^/app/bin/steam$': Flatpak Steam binary
    #   - pgrep -f 'flatpak run com.valvesoftware.Steam': Flatpak Steam launcher
    if pgrep -x steam >/dev/null \
        || pgrep -f '^/app/bin/steam$' >/dev/null \
        || pgrep -f 'flatpak run com.valvesoftware.Steam' >/dev/null; then
        steam_running=1
    fi
    # If Steam is running, halve the count (rounding up) to account for Steam Input duplicates
    if [ "$steam_running" -eq 1 ]; then
        count=$(( (count + 1) / 2 ))
    fi
    # Clamp the count between 1 and 4
    [ "$count" -gt 4 ] && count=4
    [ "$count" -lt 1 ] && count=1
    # Output the detected controller count
    echo "$count"
}

# =============================
# Function: setSplitscreenModeForPlayer
# =============================
# Writes the splitscreen.properties config for the splitscreen mod for each player instance.
# This tells the mod which part of the screen each instance should use.
# Arguments:
#   $1 = Player number (1–4)
#   $2 = Total number of controllers/players
setSplitscreenModeForPlayer() {
    local player=$1
    local numberOfControllers=$2
    local config_path="$LAUNCHER_DIR/instances/latestUpdate-${player}/.minecraft/config/splitscreen.properties"
    mkdir -p "$(dirname "$config_path")" || return 1
    local mode="FULLSCREEN"
    # Decide the splitscreen mode for this player based on total controllers
    case "$numberOfControllers" in
        1)
            mode="FULLSCREEN" # Single player: use whole screen
            ;;
        2)
            if [ "$player" = 1 ]; then mode="TOP"; else mode="BOTTOM"; fi # 2 players: split top/bottom
            ;;
        3)
            if [ "$player" = 1 ]; then mode="TOP";
            elif [ "$player" = 2 ]; then mode="BOTTOM_LEFT";
            else mode="BOTTOM_RIGHT"; fi # 3 players: 1 top, 2 bottom corners
            ;;
        4)
            if [ "$player" = 1 ]; then mode="TOP_LEFT";
            elif [ "$player" = 2 ]; then mode="TOP_RIGHT";
            elif [ "$player" = 3 ]; then mode="BOTTOM_LEFT";
            else mode="BOTTOM_RIGHT"; fi # 4 players: 4 corners
            ;;
    esac
    # Write the config file for the mod
    printf 'gap=1\nmode=%s\n' "$mode" > "$config_path" || return 1
    logEvent INFO "layout_selected player=$player players=$numberOfControllers mode=$mode"
    sync
    sleep 0.5
}

# =============================
# Function: launchGames
# =============================
# Hides panels, launches the correct number of Minecraft instances, and restores panels after.
# Handles all splitscreen logic and per-player config.
launchGames() {
    local -a controller_devices
    mapfile -t controller_devices < <(getControllerDevices)
    numberOfControllers="${MSS_PLAYERS:-${#controller_devices[@]}}"
    if ! [[ "$numberOfControllers" =~ ^[1-4]$ ]]; then
        echo '[Error] Connect 1–4 controllers or set MSS_PLAYERS=1..4.' >&2
        logEvent ERROR "invalid_player_count count=$numberOfControllers"
        return 1
    fi
    if [ "$numberOfControllers" -gt "${#controller_devices[@]}" ]; then
        echo '[Error] Fewer independently detected controllers than requested players.' >&2
        logEvent ERROR "insufficient_controllers players=$numberOfControllers detected=${#controller_devices[@]}"
        return 1
    fi

    if [ "${#controller_devices[@]}" -gt 0 ]; then
        echo "[Info] Detected joystick devices for assignment: ${controller_devices[*]}"
    else
        echo "[Info] No joystick devices detected for per-instance input pinning"
    fi

    local player
    for player in $(seq 1 "$numberOfControllers"); do
        local joystick_device=""
        if [ "$player" -le "${#controller_devices[@]}" ]; then
            joystick_device="${controller_devices[$((player-1))]}"
        fi
        if [ -n "$joystick_device" ] && [ ! -r "$joystick_device" ]; then
            logEvent ERROR "controller_access_denied player=$player device=$joystick_device"
            echo "[Error] Controller $joystick_device is not readable in this session." >&2
            return 1
        fi
        if [ "$player" -gt 1 ]; then
            pruneLauncherFrontends "pre-launch latestUpdate-$player"
        fi
        if [ -n "$(findGamePid "latestUpdate-$player")" ]; then
            logEvent ERROR "instance_already_running player=$player"
            return 1
        fi
        clearControllableSelection "latestUpdate-$player"
        configureInstanceControllerWrapper "latestUpdate-$player" "$joystick_device" || return 1
        setSplitscreenModeForPlayer "$player" "$numberOfControllers" || return 1
        # Do not throttle or pause the unfocused players. Explicitly persist
        # vanilla's pause-on-focus option; controller mod behavior still needs
        # verification on real hardware.
        local options="$LAUNCHER_DIR/instances/latestUpdate-$player/.minecraft/options.txt"
        if [ -f "$options" ]; then
            sed -i '/^pauseOnLostFocus:/d' "$options" || return 1
        fi
        printf 'pauseOnLostFocus:false\n' >> "$options" || return 1
        launchGame "latestUpdate-$player" "P$player" "$joystick_device" || return 1
    done
    waitForGames
}

# =============================
# Function: isGamingMode
# =============================
# Detect Steam Gaming Mode independently of hardware model and username. This
# covers Steam Deck, Bazzite HTPC and other gamescope-session installations.
isGamingMode() {
    case "${MSS_GAME_MODE:-auto}" in
        1|true|yes) return 0 ;;
        0|false|no) return 1 ;;
    esac

    if [[ "${XDG_SESSION_DESKTOP:-}" =~ [Gg][Aa][Mm][Ee][Ss][Cc][Oo][Pp][Ee] ]] || \
       [[ "${XDG_CURRENT_DESKTOP:-}" =~ [Gg][Aa][Mm][Ee][Ss][Cc][Oo][Pp][Ee] ]]; then
        return 0
    fi

    if [ "${SteamGamepadUI:-0}" = "1" ] || [ "${STEAM_GAMEPADUI:-0}" = "1" ]; then
        return 0
    fi

    # Big Picture on GNOME Desktop is not an embedded Gamescope session.
    return 1
}

isBazzite() {
    case "${MSS_BAZZITE:-auto}" in
        1|true|yes) return 0 ;;
        0|false|no) return 1 ;;
    esac
    [ -r /etc/os-release ] && grep -Eqi '^(ID|ID_LIKE|VARIANT_ID)=.*bazzite' /etc/os-release
}

selectNestedCompositor() {
    case "$MSS_COMPOSITOR" in
        plasma|mutter|direct) printf '%s\n' "$MSS_COMPOSITOR"; return 0 ;;
        auto) ;;
        *)
            echo "[Error] Invalid MSS_COMPOSITOR '$MSS_COMPOSITOR' (use auto, plasma, mutter or direct)." >&2
            return 1
            ;;
    esac

    # Prefer Mutter on the Bazzite GNOME image. It is already part of the base
    # deployment and avoids rpm-ostree layering of Plasma packages.
    if isBazzite && command -v mutter >/dev/null 2>&1 && \
       [[ "${XDG_CURRENT_DESKTOP:-}" =~ GNOME|gamescope|Gamescope ]]; then
        printf '%s\n' mutter
    elif command -v startplasma-wayland >/dev/null 2>&1 && \
         command -v kwin_wayland_wrapper >/dev/null 2>&1; then
        printf '%s\n' plasma
    elif command -v mutter >/dev/null 2>&1; then
        printf '%s\n' mutter
    else
        echo '[Error] No nested compositor is available. Use --diagnose and see TESTING.md.' >&2
        return 1
    fi
}

# =============================
# Always remove the autostart file on script exit to prevent unwanted autostart on boot
cleanup_autostart() {
    local rc=$?
    if [ "${MSS_CREATED_AUTOSTART:-0}" = 1 ]; then
        rm -f "$HOME/.config/autostart/minecraft-launch.desktop"
    fi
    if [ "$rc" -ne 0 ]; then
        local index pid
        for index in "${!MSS_GAME_PIDS[@]}"; do
            pid="${MSS_GAME_PIDS[$index]}"
            if [ -n "$pid" ] && [ "$(findGamePid "${MSS_GAME_INSTANCES[$index]}")" = "$pid" ]; then
                kill -TERM "$pid" 2>/dev/null
            fi
        done
        stopTrackedFrontends
    fi
    logEvent INFO "launcher_exit rc=$rc"
    return "$rc"
}
trap cleanup_autostart EXIT
stopGames() {
    local index pid
    logEvent WARN 'signal_received stopping_tracked_games'
    for index in "${!MSS_GAME_PIDS[@]}"; do
        pid="${MSS_GAME_PIDS[$index]}"
        if [ -n "$pid" ] && [ "$(findGamePid "${MSS_GAME_INSTANCES[$index]}")" = "$pid" ]; then
            kill -TERM "$pid" 2>/dev/null
        fi
    done
    exit 130
}
trap stopGames INT TERM


# =============================
# MAIN LOGIC: Entry Point
# =============================
# Universal: Steam Gaming Mode = nested compositor, else launch on current desktop
if [ "${1:-}" = "--diagnose" ]; then
    printf 'gaming_mode=%s\n' "$(isGamingMode && echo yes || echo no)"
    printf 'bazzite=%s\n' "$(isBazzite && echo yes || echo no)"
    detected_compositor="$(selectNestedCompositor)"
    compositor_status=$?
    printf 'compositor=%s\n' "${detected_compositor:-unavailable}"
    printf 'resolution=%s\n' "$(getOutputResolution)"
    for dependency in mutter dbus-run-session Xwayland xdpyinfo flock python3; do
        printf 'dependency_%s=%s\n' "$dependency" "$(command -v "$dependency" || echo missing)"
    done
    exit "$compositor_status"
fi

if [ "${1:-}" != launchFromPlasma ] && [ "${1:-}" != launchFromMutter ]; then
    command -v flock >/dev/null || { echo '[Error] flock is required.' >&2; exit 1; }
    exec 9> "$LAUNCHER_DIR/splitscreen.lock"
    flock -n 9 || { echo '[Error] Another splitscreen session is active.' >&2; exit 1; }
fi

if [ "${1:-}" = launchFromPlasma ] || [ "${1:-}" = launchFromMutter ]; then
    logEvent INFO "nested_ready stage=$1 display=${DISPLAY:-unset} wayland=${WAYLAND_DISPLAY:-unset}"
    if [ -z "${DISPLAY:-}" ]; then
        echo '[Error] Nested Xwayland DISPLAY is unset; Java windows cannot be routed safely.' >&2
        exit 1
    fi
    if [ "${1:-}" = launchFromMutter ] && [ -n "${MSS_PARENT_DISPLAY:-}" ] && [ "$DISPLAY" = "$MSS_PARENT_DISPLAY" ]; then
        logEvent ERROR 'nested_display_matches_parent refusing_outer_window_launch'
        echo '[Error] Mutter did not provide a distinct Xwayland DISPLAY; see compositor.log.' >&2
        exit 1
    fi
    if [ "${1:-}" = launchFromPlasma ]; then
        # Inside nested Plasma session: launch Minecraft splitscreen and logout when done
        rm -f ~/.config/autostart/minecraft-launch.desktop
        launchGames
        game_status=$?
        qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout
        exit "$game_status"
    elif [ "${1:-}" = launchFromMutter ]; then
        # Mutter exits automatically when its child command finishes.
        launchGames
    fi
elif isGamingMode; then
        compositor="$(selectNestedCompositor)" || exit 1
        case "$compositor" in
            plasma) nestedPlasma ;;
            mutter) nestedMutter ;;
            direct)
                echo "[Warning] No supported nested compositor found; launching directly."
                launchGames
                ;;
        esac
else
    launchGames
fi
