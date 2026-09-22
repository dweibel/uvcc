#!/usr/bin/env bash

# Apply personal pan/tilt/zoom defaults to the Logitech C925e.
# Adjust the values below to taste; the camera's own neutral position is
# pan/tilt 0 0 and zoom 100 (the minimum).

set -o errexit
set -o noclobber
set -o nounset
set -o pipefail

# Camera preset.
declare -r -i PAN=7200
declare -r -i TILT=0
declare -r -i ZOOM=200

# Device selection, so a multi-camera setup still targets the C925e.
declare -r -i VENDOR=1133
declare -r -i PRODUCT=2139

declare -r SCRIPT_BASE="${BASH_SOURCE%/*}"
declare SCRIPT_BASE_ABSOLUTE
SCRIPT_BASE_ABSOLUTE="$(realpath "$SCRIPT_BASE")"
declare -r SCRIPT_BASE_ABSOLUTE

# NOTE: ~/.zshrc loads nvm only for interactive shells, so node may be missing
# when this script runs from cron, a launch agent, or another script.
if ! command -v node >/dev/null 2>&1 && [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
	# shellcheck disable=SC1091
	. "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
fi

if ! command -v node >/dev/null 2>&1; then
	echo 'Could not find node.' >&2
	exit 1
fi

# Prefer a globally installed uvcc, fall back to this repository's build.
declare -a UVCC
if command -v uvcc >/dev/null 2>&1; then
	UVCC=(uvcc)
else
	declare UVCC_INDEX
	UVCC_INDEX="$(realpath "${SCRIPT_BASE_ABSOLUTE}/dist/index.js")"

	if [[ ! -f "$UVCC_INDEX" ]]; then
		echo "Could not find ${UVCC_INDEX}. Run 'npm run rebuild' first." >&2
		exit 1
	fi

	UVCC=(node -- "$UVCC_INDEX")
fi

declare -r -a UVCC_DEVICE=("${UVCC[@]}" --vendor "$VENDOR" --product "$PRODUCT")

# Zoom first: pan/tilt only has room to move once the crop is applied, and the
# camera needs a moment before it honors the pan.
"${UVCC_DEVICE[@]}" set absolute_zoom "$ZOOM"
sleep 0.5
"${UVCC_DEVICE[@]}" set absolute_pan_tilt "$PAN" "$TILT"

echo "Applied pan/tilt ${PAN} ${TILT} and zoom ${ZOOM}." >&2
