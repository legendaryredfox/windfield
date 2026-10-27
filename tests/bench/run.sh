#!/bin/sh
# Run from the repository root: xvfb-run -a sh tests/bench/run.sh [--table]
# LÖVE cannot require files outside its source directory, so the benchmark and
# the library are copied to a temp dir.
set -e
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp tests/bench/main.lua tests/bench/conf.lua "$dir"/
cp -r windfield "$dir/windfield"
if [ "$1" = "--table" ]; then
    love "$dir" | grep '^RESULT' | lua tests/bench/table.lua
else
    love "$dir" | grep '^RESULT'
fi
