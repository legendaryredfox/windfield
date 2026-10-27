#!/bin/sh
# Run from the repository root: sh tests/run_all.sh
# Runs the mocked-love suite on every installed interpreter, then the real LÖVE
# smoke script when `love` is available. LÖVE always runs under xvfb-run so no
# window opens on the real display.
failed=0
found=0
for lua in luajit lua5.1 lua5.4 lua5.5 lua; do
    command -v "$lua" >/dev/null 2>&1 || continue
    found=$((found + 1))
    printf '%s: ' "$lua"
    "$lua" tests/run.lua || failed=1
done
if [ "$found" -eq 0 ]; then
    echo 'no Lua interpreter found'
    failed=1
fi
if command -v love >/dev/null 2>&1; then
    echo 'smoke:'
    if command -v xvfb-run >/dev/null 2>&1; then
        output=$(timeout 120 xvfb-run -a sh tests/smoke/run.sh 2>&1)
    else
        echo 'xvfb-run not found, skipping the smoke script'
        exit $failed
    fi
    echo "$output" | grep -E '^(ok|FAIL)|eprecat'
    if echo "$output" | grep -q '^FAIL' || ! echo "$output" | grep -q '^ok'; then failed=1; fi
fi
exit $failed
