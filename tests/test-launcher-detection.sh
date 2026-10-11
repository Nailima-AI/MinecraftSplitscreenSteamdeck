#!/bin/bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/home/.local/share/minecraft-splitscreen/PrismLauncher" "$TEST_ROOT/bin"
touch "$TEST_ROOT/home/.local/share/minecraft-splitscreen/PrismLauncher/PrismLauncher.AppImage"
chmod +x "$TEST_ROOT/home/.local/share/minecraft-splitscreen/PrismLauncher/PrismLauncher.AppImage"

for command_name in mutter xdpyinfo; do
    cat > "$TEST_ROOT/bin/$command_name" <<'EOF'
#!/bin/sh
if [ "$(basename "$0")" = xdpyinfo ]; then
    echo '  dimensions:    1920x1080 pixels (508x285 millimeters)'
fi
EOF
    chmod +x "$TEST_ROOT/bin/$command_name"
done

run_diagnose() {
    env \
        HOME="$TEST_ROOT/home" \
        PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
        MSS_DISABLE_SELF_UPDATE=1 \
        "$@" \
        bash "$REPO_DIR/minecraftSplitscreen.sh" --diagnose
}

assert_contains() {
    local output="$1" expected="$2"
    if ! grep -Fqx "$expected" <<<"$output"; then
        echo "Expected diagnostic line: $expected" >&2
        echo "$output" >&2
        exit 1
    fi
}

output="$(run_diagnose MSS_GAME_MODE=1 MSS_BAZZITE=1 XDG_CURRENT_DESKTOP=gamescope XDG_SESSION_DESKTOP=gamescope)"
assert_contains "$output" 'gaming_mode=yes'
assert_contains "$output" 'bazzite=yes'
assert_contains "$output" 'compositor=mutter'
assert_contains "$output" 'resolution=1920x1080'

output="$(run_diagnose MSS_GAME_MODE=0 MSS_BAZZITE=0 MSS_COMPOSITOR=direct MSS_RESOLUTION=3840x2160)"
assert_contains "$output" 'gaming_mode=no'
assert_contains "$output" 'bazzite=no'
assert_contains "$output" 'compositor=direct'
assert_contains "$output" 'resolution=3840x2160'

echo 'launcher detection tests passed'
