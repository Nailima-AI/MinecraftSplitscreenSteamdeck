#!/bin/bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/home/.local/share/minecraft-splitscreen/PrismLauncher" "$TEST_ROOT/bin"
touch "$TEST_ROOT/home/.local/share/minecraft-splitscreen/PrismLauncher/PrismLauncher.AppImage"
chmod +x "$TEST_ROOT/home/.local/share/minecraft-splitscreen/PrismLauncher/PrismLauncher.AppImage"

cat > "$TEST_ROOT/bin/mutter" <<'EOF'
#!/bin/sh
{
    printf 'resolution=%s\n' "$MUTTER_DEBUG_DUMMY_MODE_SPECS"
    printf 'args='
    printf '%s ' "$@"
    printf '\n'
} > "$MSS_TEST_RECORD"
EOF
chmod +x "$TEST_ROOT/bin/mutter"
cp "$TEST_ROOT/bin/mutter" "$TEST_ROOT/bin/Xwayland"

cat > "$TEST_ROOT/bin/dbus-run-session" <<'EOF'
#!/bin/sh
if [ "${1:-}" = -- ]; then
    shift
fi
exec "$@"
EOF
chmod +x "$TEST_ROOT/bin/dbus-run-session"

record="$TEST_ROOT/mutter-record"
env \
    HOME="$TEST_ROOT/home" \
    PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
    MSS_DISABLE_SELF_UPDATE=1 \
    MSS_GAME_MODE=1 \
    WAYLAND_DISPLAY=wayland-mock \
    MSS_BAZZITE=1 \
    MSS_COMPOSITOR=mutter \
    MSS_RESOLUTION=2560x1440 \
    MSS_TEST_RECORD="$record" \
    bash "$REPO_DIR/minecraftSplitscreen.sh"

grep -Fqx 'resolution=2560x1440' "$record"
grep -Fq -- '--wayland --nested --' "$record"
grep -Fq 'launchFromMutter' "$record"

echo 'nested Mutter launch test passed'
