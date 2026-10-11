#!/bin/bash
# =============================================================================
# LAUNCHER SETUP MODULE
# =============================================================================
# PrismLauncher setup functions
# PrismLauncher is used as the primary launcher for splitscreen gameplay

# download_prism_launcher: Download the latest PrismLauncher AppImage
# We download it to the target directory for splitscreen launcher usage
download_prism_launcher() {
    if [[ "$(uname -m)" != x86_64 ]]; then
        print_error "This HTPC archive currently supports x86_64 only."
        return 1
    fi
    # Skip download if AppImage already exists
    if [[ -s "$TARGET_DIR/PrismLauncher.AppImage" ]]; then
        chmod +x "$TARGET_DIR/PrismLauncher.AppImage"
        print_success "PrismLauncher AppImage already present"
        return 0
    fi
    
    print_progress "Downloading latest PrismLauncher AppImage..."
    
    # Query GitHub API to get the latest release download URL
    # We specifically look for AppImage files in the release assets
    local prism_url
    prism_url=$(curl -fsSL --connect-timeout 15 --max-time 60 https://api.github.com/repos/PrismLauncher/PrismLauncher/releases/latest | \
        jq -r '[.assets[]
            | select(
                (.name | ascii_downcase | endswith("appimage"))
                and (
                    (.name | ascii_downcase | contains("x86_64"))
                    or (.name | ascii_downcase | contains("amd64"))
                )
            )
            | .browser_download_url] | .[0] // empty') || return 1
    
    # Validate that we got a valid download URL
    if [[ -z "$prism_url" || "$prism_url" == "null" ]]; then
        print_error "Could not find latest PrismLauncher AppImage URL."
        print_error "Please check https://github.com/PrismLauncher/PrismLauncher/releases manually."
        exit 1
    fi
    
    # Download and make executable
    local download_temp
    download_temp="$(mktemp "$TARGET_DIR/PrismLauncher.AppImage.XXXXXX")" || return 1
    if ! curl -fL --connect-timeout 15 --max-time 600 "$prism_url" -o "$download_temp"; then
        rm -f -- "$download_temp"
        return 1
    fi
    mv -- "$download_temp" "$TARGET_DIR/PrismLauncher.AppImage" || return 1
    chmod +x "$TARGET_DIR/PrismLauncher.AppImage"
    print_success "PrismLauncher AppImage downloaded successfully"
}

# configure_prismlauncher_defaults: Write a baseline PrismLauncher config to avoid first-run setup prompts.
configure_prismlauncher_defaults() {
    print_progress "Configuring PrismLauncher defaults (Java + memory)..."

    local cfg_path="$TARGET_DIR/prismlauncher.cfg"
    if [[ -s "$cfg_path" ]]; then
        print_info "Preserving existing PrismLauncher preferences. Set Java in the launcher if changing game versions."
        return 0
    fi
    local current_hostname
    if command -v hostname >/dev/null 2>&1; then
        current_hostname=$(hostname)
    elif [[ -n "${HOSTNAME:-}" ]]; then
        current_hostname="$HOSTNAME"
    else
        current_hostname="localhost"
    fi

    local java_cfg_path="${JAVA_PATH:-java}"
    cat > "$cfg_path" <<EOF
[General]
ApplicationTheme=system
ConfigVersion=1.2
SkipJavaWizard=true
IconTheme=pe_colored
JavaPath=${java_cfg_path}
Language=en_US
LastHostname=${current_hostname}
MaxMemAlloc=4096
MinMemAlloc=512
ToolbarsLocked=false
EOF

    print_success "PrismLauncher defaults written: $cfg_path"
    return 0
}

# setup_splitscreen_launcher_script: Install minecraftSplitscreen.sh into TARGET_DIR
# Require the bundled experimental launcher, never substitute upstream.
setup_splitscreen_launcher_script() {
    print_progress "Installing splitscreen launcher script..."

    local launcher_script="$TARGET_DIR/minecraftSplitscreen.sh"
    local local_script="${SCRIPT_DIR:-}/minecraftSplitscreen.sh"
    local repo_slug="${MSS_REPO_SLUG:-FlyingEwok/MinecraftSplitscreenSteamdeck}"
    local remote_script="https://raw.githubusercontent.com/${repo_slug}/main/minecraftSplitscreen.sh"

    if [[ -f "$local_script" ]]; then
        cp "$local_script" "$launcher_script"
    else
        print_error "Bundled Prism splitscreen launcher is missing. Extract the complete archive."
        return 1
    fi

    chmod +x "$launcher_script"
    if [[ -f "${SCRIPT_DIR:-}/collect-debug.py" ]]; then
        cp -- "$SCRIPT_DIR/collect-debug.py" "$TARGET_DIR/collect-debug.py"
        chmod +x "$TARGET_DIR/collect-debug.py"
    fi
    print_success "Splitscreen launcher script installed: $launcher_script"
    return 0
}
