#!/bin/sh
# Run from the repository root. LÖVE cannot require files outside its source
# directory, so the smoke script and the library are copied to a temp dir.
# SMOKE_HEADLESS=1 disables the window and graphics modules and runs only the
# physics checks (LÖVE 12 builds need a Vulkan GPU for graphics).
# SMOKE_LOVE overrides the command, e.g. SMOKE_LOVE="/path/love.AppImage --appimage-extract-and-run".
set -e
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp tests/smoke/main.lua "$dir/main.lua"
cp -r windfield "$dir/windfield"
cp -r tests/fixtures "$dir/fixtures"
if [ -n "$SMOKE_HEADLESS" ]; then
    cat > "$dir/conf.lua" <<'CONF'
function love.conf(t)
    t.modules.window = false
    t.modules.graphics = false
    t.modules.audio = false
    t.modules.sound = false
    t.modules.joystick = false
end
CONF
fi
${SMOKE_LOVE:-love} "$dir"
