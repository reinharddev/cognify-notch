#!/bin/zsh
# Build Cognify Notch.app + DMG: ./build.sh <versi> [--no-notarize]
cd "$(dirname "$0")"
NOTCH_DIR=. NOTCH_ICON=AppIcon.icns exec zsh scripts/build-notch-app.sh "$@"
