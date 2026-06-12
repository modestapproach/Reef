#!/bin/zsh
# Build Reef (Release) and install to /Applications.
#
# Signs with the self-signed "Reef Local Dev" identity so the signature is
# STABLE across rebuilds — macOS TCC grants (Accessibility, Screen Recording)
# key on the signature, so this means granting each permission once instead
# of after every build. Sparkle.framework ships with its own Team ID
# signature; an identity-signed main binary refuses to load it, so we strip
# and deep re-sign everything with the same identity.
set -e
cd "$(dirname "$0")"

IDENTITY="Reef Local Dev"

xcodebuild -project Reef.xcodeproj -scheme Reef -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

APP=build/Build/Products/Release/Reef.app
codesign --remove-signature "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
codesign --force --deep -s "$IDENTITY" "$APP"

osascript -e 'tell application "Reef" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/Reef.app
cp -R "$APP" /Applications/Reef.app
open /Applications/Reef.app

echo ""
echo "Installed. Signature is stable across rebuilds — permissions persist."
