#!/bin/zsh
# Unduh Sparkle (pembaru otomatis app Mac, lisensi MIT) ke notch/.sparkle/ jika belum ada.
# Versi & SHA-256 dikunci supaya yang dipakai selalu file yang sama persis.
set -euo pipefail
cd "$(dirname "$0")/.."
cd "${NOTCH_DIR:-notch}" # repo cognify-notch: NOTCH_DIR=.
VERSION=2.10.0
SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
DIR=.sparkle
[[ -f "$DIR/.version" && "$(cat $DIR/.version)" == "$VERSION" ]] && exit 0
rm -rf "$DIR" && mkdir -p "$DIR"
curl -fsSL -o "$DIR/sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
echo "$SHA256  $DIR/sparkle.tar.xz" | shasum -a 256 -c - >/dev/null || { echo "Checksum Sparkle tidak cocok" >&2; rm -rf "$DIR"; exit 1; }
tar -xf "$DIR/sparkle.tar.xz" -C "$DIR"
rm "$DIR/sparkle.tar.xz"
echo "$VERSION" > "$DIR/.version"
echo "Sparkle $VERSION siap di notch/$DIR"
