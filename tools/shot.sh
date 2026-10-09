#!/usr/bin/env bash
# Render the TV to a PNG: tools/shot.sh out.png [--moves N] [--seed N] [--yaw D]
# Needs xvfb-run and a Vulkan driver (lavapipe works).
set -euo pipefail
out=$(realpath -m "$1"); shift
cd "$(dirname "$0")/.."
xvfb-run -a -s "-screen 0 1920x1080x24" "${GODOT:-godot}" --rendering-driver vulkan --resolution 1920x1080 --path . -- --shot "$out" "$@"
