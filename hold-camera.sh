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
#
# When another client takes the format, the picture pans out until camhold
# takes it back. CAMHOLD_SETTLE is how long an off-size stream is tolerated
# before that happens, and so is the visible length of the glitch;
# CAMHOLD_RETRY spaces out further attempts if the client keeps insisting.

set -o errexit
set -o nounset
set -o pipefail

declare -r SIZE="${CAMHOLD_SIZE:-1024x576}"
declare -r SETTLE="${CAMHOLD_SETTLE:-0.05}"
declare -r RETRY="${CAMHOLD_RETRY:-0.2}"

declare -r SCRIPT_BASE="${BASH_SOURCE%/*}"
declare SCRIPT_BASE_ABSOLUTE
SCRIPT_BASE_ABSOLUTE="$(realpath "$SCRIPT_BASE")"
declare -r SCRIPT_BASE_ABSOLUTE

declare -r CAMHOLD="${SCRIPT_BASE_ABSOLUTE}/camhold"

declare -r CAMHOLD_SOURCE="${SCRIPT_BASE_ABSOLUTE}/camhold.swift"

# Rebuild when the binary is missing or older than the source, so an edit to
# camhold.swift is not silently ignored in favor of a stale build.
if [[ ! -x "$CAMHOLD" || "$CAMHOLD_SOURCE" -nt "$CAMHOLD" ]]; then
	if ! command -v swiftc >/dev/null 2>&1; then
		echo 'Could not find swiftc to build camhold (install Xcode Command Line Tools).' >&2
		exit 1
	fi

	echo 'Building camhold...' >&2
	swiftc -O -o "$CAMHOLD" "$CAMHOLD_SOURCE"
fi

"$CAMHOLD" --size "$SIZE" --settle "$SETTLE" --retry "$RETRY" &
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
