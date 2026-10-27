#!/bin/sh
# Run from the repository root. LÖVE cannot require files outside its source
# directory, so the smoke script and the library are copied to a temp dir.
set -e
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp tests/smoke/main.lua "$dir/main.lua"
cp -r windfield "$dir/windfield"
love "$dir"
