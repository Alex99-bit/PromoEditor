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
cp "$BIN_PATH/PromoEditorCLI" dist/PromoEditorCLI
codesign --force --deep --sign - "$APP"
codesign --force --sign - dist/PromoEditorCLI

echo "Aplicación creada en: $PWD/$APP"
