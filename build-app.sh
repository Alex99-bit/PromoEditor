#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

APP="dist/Promo Editor.app"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BIN_PATH/PromoEditor" "$APP/Contents/MacOS/PromoEditor"
codesign --force --deep --sign - "$APP"

echo "Aplicación creada en: $PWD/$APP"
