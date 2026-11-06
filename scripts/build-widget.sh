#!/bin/zsh
# Ekstensi widget macOS Cognify Notch (WidgetKit), dirakit tanpa proyek Xcode: swiftc langsung.
# Pakai: build-widget.sh <folder-keluar> <identitas-tanda-tangan|-> [versi]
# Hasil: <folder-keluar>/CognifyWidgets.appex (universal, macOS 14+), ditandatangani dan ber-sandbox.
# Dipanggil build-notch-app.sh sebelum app ditandatangani; app memasangnya di Contents/PlugIns.
set -euo pipefail
cd "$(dirname "$0")/.."
N=${NOTCH_DIR:-notch}
OUT=$1; ID=$2; VERSION=${3:-1.0.0}
APPEX="$OUT/CognifyWidgets.appex"
TMP=$(mktemp -d)
rm -rf "$APPEX"
mkdir -p "$APPEX/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -module-name CognifyWidgets -target $arch-apple-macos14.0 \
    -application-extension -Xlinker -e -Xlinker _NSExtensionMain \
    -framework WidgetKit -framework SwiftUI \
    "$N"/Widget/*.swift "$N/Sources/CognifyNotch/WidgetShared.swift" -o "$TMP/w-$arch"
done
lipo -create "$TMP/w-arm64" "$TMP/w-x86_64" -output "$APPEX/Contents/MacOS/CognifyWidgets"
cp "$N/Widget/Info.plist" "$APPEX/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$APPEX/Contents/Info.plist"
TS=(--timestamp); [[ "$ID" == "-" ]] && TS=()
codesign --force "${TS[@]}" --options runtime --entitlements "$N/Widget/entitlements.plist" --sign "$ID" "$APPEX"
rm -rf "$TMP"
echo "Widget: $APPEX"
