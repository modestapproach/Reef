#!/bin/zsh
# Build Reef (Release, ad-hoc signed) and install to /Applications.
# Sparkle.framework ships with its own Team ID signature; an ad-hoc main
# binary refuses to load it, so we strip and deep re-sign everything ad-hoc.
set -e
cd "$(dirname "$0")"

xcodebuild -project Reef.xcodeproj -scheme Reef -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

APP=build/Build/Products/Release/Reef.app
codesign --remove-signature "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
codesign --force --deep -s - "$APP"

osascript -e 'tell application "Reef" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/Reef.app
cp -R "$APP" /Applications/Reef.app
open /Applications/Reef.app

echo ""
echo "Installed. Ad-hoc signature changed -> re-grant Accessibility:"
echo "System Settings -> Privacy & Security -> Accessibility:"
echo "remove Reef (-), re-add /Applications/Reef.app, toggle on."
