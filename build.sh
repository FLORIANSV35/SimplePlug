#!/bin/bash
# Builds SimplePlug.app (only needs the Command Line Tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/SimplePlug.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macos12.0" \
    Sources/*.swift \
    -framework AppKit -framework AVFoundation -framework CoreAudio \
    -framework AudioToolbox -framework CoreAudioKit \
    -o "$APP/Contents/MacOS/SimplePlug"

# Version YY.MM.XX computed from the git history (see version.sh); stamped into the built Info.plist.
VERSION="$(./version.sh --plain 2>/dev/null || echo 0.0.0)"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "OK → $APP (version $VERSION)"
echo "Run: open \"$APP\""
