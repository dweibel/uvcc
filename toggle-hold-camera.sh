#!/usr/bin/env bash

# Start ./hold-camera.sh in the background, or stop it if it is already
# running. Meant to be called from a Desktop launcher or a keyboard shortcut,
# where there is no terminal to press Ctrl-C in. Posts a notification either
# way; the holder's output goes to $TMPDIR/hold-camera.log.

set -o errexit
set -o nounset
set -o pipefail

declare -r SCRIPT_BASE="${BASH_SOURCE%/*}"
declare SCRIPT_BASE_ABSOLUTE
SCRIPT_BASE_ABSOLUTE="$(realpath "$SCRIPT_BASE")"
declare -r SCRIPT_BASE_ABSOLUTE

declare -r RUN_DIR="${TMPDIR:-/tmp}"
declare -r PID_FILE="${RUN_DIR}/hold-camera.pid"
declare -r LOG_FILE="${RUN_DIR}/hold-camera.log"

notify() {
	osascript -e "display notification \"$1\" with title \"Hold Camera\"" >/dev/null 2>&1 || true
	echo "$1" >&2
}

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
	kill -TERM "$(cat "$PID_FILE")"
	rm -f "$PID_FILE"
	notify "Camera released."
else
	rm -f "$PID_FILE"
	nohup "${SCRIPT_BASE_ABSOLUTE}/hold-camera.sh" >"$LOG_FILE" 2>&1 &
	echo $! >"$PID_FILE"
	notify "Holding the camera at ${CAMHOLD_SIZE:-1024x576}."
fi
