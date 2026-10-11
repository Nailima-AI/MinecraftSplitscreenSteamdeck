#!/bin/bash
# =============================================================================
# Minecraft Splitscreen Steam Deck Installer - Main Workflow Module
# =============================================================================
# 
# This module contains the main orchestration logic for the complete splitscreen
# installation process. It coordinates all the other modules and provides
# comprehensive status reporting and user guidance.
#
# Functions provided:
# - main: Primary function that orchestrates the complete installation process
#
# =============================================================================

# main: Primary function that orchestrates the complete splitscreen installation process
#
# INSTALLATION WORKFLOW:
# 1. WORKSPACE SETUP: Create directories and initialize environment
# 2. CORE SETUP: Java detection and PrismLauncher download
# 3. VERSION DETECTION: Minecraft and Fabric version determination
# 4. ACCOUNT SETUP: Download offline splitscreen player accounts
# 5. MOD COMPATIBILITY: Query APIs and determine compatible mod versions
# 6. USER SELECTION: Interactive mod selection interface
# 7. INSTANCE CREATION: Create 4 splitscreen instances with manual configuration
# 8. INTEGRATION: Optional Steam and desktop launcher integration
# 9. COMPLETION: Summary report and usage instructions
#
# ERROR HANDLING STRATEGY:
# - Each phase has fallback mechanisms to ensure installation can complete
# - Non-critical integration failures don't halt the entire process
# - Comprehensive error reporting helps users understand any issues
# - Multiple validation checkpoints ensure data integrity
#
# LAUNCHER APPROACH:
# The script uses PrismLauncher as the primary launcher for day-to-day splitscreen gameplay.
main() {
    # Support direct module testing calls with --debug.
    local arg
    for arg in "$@"; do
        if [[ "$arg" == "--debug" ]]; then
            DEBUG_MODE=true
        fi
    done

    print_header "🎮 MINECRAFT SPLITSCREEN INSTALLER 🎮"
    print_info "PrismLauncher launcher setup with manual instance creation"
    print_debug "Debug logging enabled"
    echo ""
    # Controllable is a required CurseForge mod. Never fetch shared credentials.
    if [[ -z "${MSS_CURSEFORGE_API_KEY:-}" ]]; then
        if [[ -t 0 ]]; then
            read -r -s -p "Your CurseForge API key (input hidden): " MSS_CURSEFORGE_API_KEY || return 1
            printf '\n'
        else
            print_error "Set MSS_CURSEFORGE_API_KEY before installing; required CurseForge mods need your own API key."
            return 1
        fi
    fi
    if [[ -z "${MSS_CURSEFORGE_API_KEY:-}" ]]; then
        print_error "A CurseForge API key is required. No shared token is bundled."
        return 1
    fi
    # API functions use the shell variable; do not pass it to unrelated children.
    export -n MSS_CURSEFORGE_API_KEY
    
    # =============================================================================
    # WORKSPACE INITIALIZATION PHASE
    # =============================================================================
    
    # WORKSPACE SETUP: Create and navigate to working directory
    # All temporary files, downloads, and initial setup happen in TARGET_DIR
    # This provides a clean, isolated environment for the installation process
    print_progress "Initializing installation workspace: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR" || exit 1
    print_success "✅ Workspace initialized successfully"
    
    # =============================================================================
    # CORE SYSTEM REQUIREMENTS VALIDATION
    # =============================================================================
    
    download_prism_launcher        # Download PrismLauncher AppImage for splitscreen launcher usage
    
    # =============================================================================
    # VERSION DETECTION AND CONFIGURATION
    # =============================================================================
    
    get_minecraft_version         # Determine target Minecraft version (user choice or latest)
    detect_java                   # Automatically detect, install, and configure correct Java version for selected Minecraft version
    configure_prismlauncher_defaults     # Write launcher defaults so Quick Setup wizard is skipped
    get_fabric_version           # Get compatible Fabric loader version from API
    get_lwjgl_version            # Detect appropriate LWJGL version for Minecraft version
    
    # =============================================================================
    # OFFLINE ACCOUNTS CONFIGURATION
    # =============================================================================
    
    print_progress "Setting up offline accounts for splitscreen gameplay..."
    print_debug "Downloading pre-configured offline accounts for Player 1-4"
    
    # OFFLINE ACCOUNTS DOWNLOAD: Get splitscreen player account configurations
    # These accounts enable splitscreen without requiring multiple Microsoft accounts
    # Each player (P1, P2, P3, P4) gets a separate offline profile for identification
    if [[ -s accounts.json ]]; then
        print_info "Preserving existing account configuration."
    elif [[ -s "${SCRIPT_DIR}/accounts.json" ]]; then
        cp -- "${SCRIPT_DIR}/accounts.json" accounts.json
        chmod 600 accounts.json
    else
        print_error "No bundled accounts.json. Extract the complete archive before installing."
        return 1
    fi
    
    # =============================================================================
    # MOD ECOSYSTEM SETUP PHASE
    # =============================================================================
    
    check_mod_compatibility       # Query Modrinth/CurseForge APIs for compatible versions
    select_user_mods             # Interactive mod selection interface with categories
    
    # =============================================================================
    # MINECRAFT INSTANCE CREATION PHASE
    # =============================================================================
    
    
    create_instances             # Create 4 splitscreen instances using manual configuration
    setup_splitscreen_launcher_script   # Install minecraftSplitscreen.sh into launcher directory
    
    # =============================================================================
    # SYSTEM INTEGRATION PHASE: Optional platform integration
    # =============================================================================
    
    setup_steam_integration     # Add splitscreen launcher to Steam library (optional)
    create_desktop_launcher     # Create native desktop launcher and app menu entry (optional)
    
    # =============================================================================
    # INSTALLATION COMPLETION AND STATUS REPORTING
    # =============================================================================
    
    print_header "🎉 INSTALLATION COMPLETE"
    
    # =============================================================================
    # MISSING MODS ANALYSIS: Report any compatibility issues
    # =============================================================================
    
    # MISSING MODS REPORT: Alert user to any mods that couldn't be installed
    # This helps users understand if specific functionality might be unavailable
    # Common causes: no Fabric version available, API changes, temporary download issues
    local missing_count=0
    if [[ ${#MISSING_MODS[@]} -gt 0 ]]; then
        missing_count=${#MISSING_MODS[@]}
    fi
    if [[ $missing_count -gt 0 ]]; then
        echo ""
        print_warning "Some optional mods could not be installed:"
        for mod in "${MISSING_MODS[@]}"; do
            echo "  ❌ $mod"
        done
        print_info "Core splitscreen functionality will still work."
    fi
    
    # =============================================================================
    # FINAL SUCCESS MESSAGE AND NEXT STEPS
    # =============================================================================
    
    echo "✅ Installation successful"
    echo "Launcher: PrismLauncher"
    echo "Instances: 4 (latestUpdate-1 to latestUpdate-4)"
    echo ""
    echo "Run: $TARGET_DIR/minecraftSplitscreen.sh"

    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
        echo ""
        echo "Debug details"
        echo "- Installation dir: $TARGET_DIR"
        echo "- Launcher executable: $TARGET_DIR/PrismLauncher.AppImage"
        echo "- Instances dir: $TARGET_DIR/instances/"
        echo "- Accounts file: $TARGET_DIR/accounts.json"
    fi

    echo ""
    echo "For troubleshooting or updates, visit:"
    echo "https://github.com/FlyingEwok/MinecraftSplitscreenSteamdeck"
    echo "=========================================="
}
