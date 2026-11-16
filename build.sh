#!/bin/bash
# Compile SimplePlug.app (nécessite seulement les Command Line Tools : xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/SimplePlug.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macos12.0" \
    Sources/*.swift \
    -framework AppKit -framework AVFoundation -framework CoreAudio \
    -framework AudioToolbox -framework CoreAudioKit \
    -o "$APP/Contents/MacOS/SimplePlug"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "OK → $APP"
echo "Lancer : open \"$APP\""
