#!/usr/bin/env bash

# Keep the Logitech C925e's pan/tilt/zoom preset in effect for Teams.
#
# The C925e only applies its digital pan/tilt/zoom at stream formats of
# 1024x576 and below. Teams opens the camera at 1280x720 or higher, where the
# crop is ignored, which is why the picture is wide even though the camera
# reports zoom 200. macOS shares a single format between every client of the
# camera and the most recent client to set one wins, so this script holds the
# camera open at a low format (via ./camhold) for as long as it runs and
# applies the preset from ./set-camera-defaults.sh. Start it before or during a
# call; stop it with Ctrl-C.

set -o errexit
set -o nounset
set -o pipefail

declare -r SIZE="${CAMHOLD_SIZE:-1024x576}"

declare -r SCRIPT_BASE="${BASH_SOURCE%/*}"
declare SCRIPT_BASE_ABSOLUTE
SCRIPT_BASE_ABSOLUTE="$(realpath "$SCRIPT_BASE")"
declare -r SCRIPT_BASE_ABSOLUTE

declare -r CAMHOLD="${SCRIPT_BASE_ABSOLUTE}/camhold"

if [[ ! -x "$CAMHOLD" ]]; then
	if ! command -v swiftc >/dev/null 2>&1; then
		echo 'Could not find swiftc to build camhold (install Xcode Command Line Tools).' >&2
		exit 1
	fi

	echo 'Building camhold...' >&2
	swiftc -O -o "$CAMHOLD" "${SCRIPT_BASE_ABSOLUTE}/camhold.swift"
fi

"$CAMHOLD" --size "$SIZE" &
declare -r HOLD_PID=$!

cleanup() {
	kill -TERM "$HOLD_PID" 2>/dev/null || true
	wait "$HOLD_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Give the holder a moment to take the format, then apply the preset.
sleep 2
"${SCRIPT_BASE_ABSOLUTE}/set-camera-defaults.sh"

echo "Holding the camera at ${SIZE}; press Ctrl-C to release it." >&2
wait "$HOLD_PID"
