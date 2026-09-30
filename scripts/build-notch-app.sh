#!/bin/zsh
# App mandiri "Cognify Notch" (tanpa Cognify) untuk dibagikan: notch/dist/Cognify Notch.app +
# notch/dist/Cognify-Notch-<versi>.dmg. Universal (Apple Silicon + Intel), macOS 13+.
#
# Tanda tangan: sertifikat "Developer ID Application" di keychain (otomatis) lalu notarisasi Apple
# dengan profil keychain `cognify-notary` (lihat scripts/release-mac.sh). `--no-notarize` = lewati
# notarisasi (untuk uji di Mac ini); tanpa sertifikat = tanda tangan ad-hoc.
# Pakai: build-notch-app.sh [versi] [--no-notarize]. Rilis + update otomatis: scripts/release-notch.sh.
#
# Update otomatis (Sparkle): app memeriksa appcast di GitHub Releases sehari sekali. Kunci publik
# EdDSA di bawah; kunci privatnya di keychain Mac pembuat rilis (generate_keys --account cognify-notch).
set -euo pipefail
cd "$(dirname "$0")/.."
# Di project Cognify notch ada di notch/; di repo cognify-notch semuanya di akar repo.
N=${NOTCH_DIR:-notch}
ICON=${NOTCH_ICON:-src-tauri/icons/icon.icns}

VERSION=1.0.0
NOTARIZE=1
for arg in "$@"; do
  case "$arg" in
    --no-notarize) NOTARIZE=0 ;;
    *) VERSION="$arg" ;;
  esac
done
NAME="Cognify Notch"
OUT=$N/dist
APP="$OUT/$NAME.app"
FEED_URL="https://github.com/reinharddev/cognify-notch/releases/latest/download/appcast.xml"
ED_PUBLIC_KEY="rPDv5/FI2CdbXxPPo1YQrSc59l8STarGA3Zqrq+XfXM="
zsh scripts/fetch-sparkle.sh

echo "1/5 Build universal…"
touch $N/Sources/CognifyNotch/main.swift # Info.plist tertanam lewat linker
swift build -c release --package-path $N --arch arm64 --arch x86_64
BIN=$N/.build/out/Products/Release # build multi-arsitektur SwiftPM
[[ -f "$BIN/cognify-notch" ]] || BIN=$N/.build/apple/Products/Release
for f in "$BIN/cognify-notch" "$BIN/libcognify-media.dylib"; do
  [[ "$(lipo -archs "$f")" == *x86_64*arm64* || "$(lipo -archs "$f")" == *arm64*x86_64* ]] || { echo "$f bukan universal" >&2; exit 1; }
done

echo "2/5 Susun app…"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN/cognify-notch" "$APP/Contents/MacOS/cognify-notch"
cp "$BIN/libcognify-media.dylib" "$APP/Contents/Frameworks/"
ditto $N/.sparkle/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework" # ditto: symlink framework tetap utuh
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp $N/Info.plist "$APP/Contents/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "$1" "$APP/Contents/Info.plist"; }
plist "Set :CFBundleIdentifier com.reinhard.cognify.notchapp"
plist "Set :CFBundleName $NAME"
plist "Add :CFBundleDisplayName string $NAME"
plist "Add :CFBundleExecutable string cognify-notch"
plist "Add :CFBundlePackageType string APPL"
plist "Add :CFBundleShortVersionString string $VERSION"
plist "Add :CFBundleVersion string $VERSION"
plist "Add :CFBundleIconFile string AppIcon"
plist "Add :LSMinimumSystemVersion string 13.0"
plist "Add :LSUIElement bool true"
plist "Add :NSHumanReadableCopyright string © Reinhard Dave Yunardi. Bagian dari Cognify (AGPL-3.0)."
plist "Add :SUFeedURL string $FEED_URL"
plist "Add :SUPublicEDKey string $ED_PUBLIC_KEY"
plist "Add :SUEnableAutomaticChecks bool true"
plist "Add :SUScheduledCheckInterval integer 86400"
plist "Add :SUAutomaticallyUpdate bool true" # unduh & pasang tanpa bertanya (bisa dimatikan di menu bar)
plist "Add :SUEnableSystemProfiling bool false"

echo "3/5 Tanda tangan…"
ID=${COGNIFY_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}
if [[ -z "$ID" ]]; then
  ID="-"
  NOTARIZE=0
  echo "   (tanpa sertifikat Developer ID: tanda tangan ad-hoc, tidak dinotarisasi)"
fi
TS=(--timestamp)
[[ "$ID" == "-" ]] && TS=()
codesign --force "${TS[@]}" --options runtime --sign "$ID" "$APP/Contents/Frameworks/libcognify-media.dylib"
# Sparkle: isi framework dulu (urutan dari dokumentasi Sparkle), baru frameworknya.
SP="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force "${TS[@]}" --options runtime --sign "$ID" "$SP/XPCServices/Installer.xpc"
codesign --force "${TS[@]}" --options runtime --preserve-metadata=entitlements --sign "$ID" "$SP/XPCServices/Downloader.xpc"
codesign --force "${TS[@]}" --options runtime --sign "$ID" "$SP/Autoupdate"
codesign --force "${TS[@]}" --options runtime --sign "$ID" "$SP/Updater.app"
codesign --force "${TS[@]}" --options runtime --sign "$ID" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force "${TS[@]}" --options runtime --entitlements $N/entitlements.plist --sign "$ID" "$APP"
codesign --verify --deep --strict "$APP"

echo "4/5 DMG…"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Cognify-Notch-$VERSION.dmg"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force "${TS[@]}" --sign "$ID" "$DMG"

if (( NOTARIZE )); then
  echo "5/5 Notarisasi Apple (biasanya 2-15 menit)…"
  xcrun notarytool submit "$DMG" --keychain-profile "${COGNIFY_NOTARY_PROFILE:-cognify-notary}" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP" # tiket yang sama; app di ZIP update ikut membawa stempel notarisasi
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
  echo "5/5 Notarisasi dilewati"
fi
echo "Selesai: $DMG"
