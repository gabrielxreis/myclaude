#!/bin/zsh
# Build My Cloud, sign it with a stable local identity (so macOS keeps the microphone and
# speech permissions across rebuilds), replace /Applications/My Cloud.app (one copy only:
# the old version is always deleted) and launch it. MYCLOUD_NO_OPEN=1 skips the launch.
# MYCLOUD_PUBLIC=1 builds the shareable version: no Mochi, no Coucou sounds in the bundle.
set -e
cd "$(dirname "$0")/../NotchBuddy"
APP="build/Build/Products/Debug/My Cloud.app"
IDENTITY="${MYCLOUD_SIGN_IDENTITY:-FrameZero Dev}"

pkill -f "My Cloud.app/Contents/MacOS" 2>/dev/null || true
rm -rf "$APP"

xcodegen >/dev/null
EXTRA=()
EXTRA=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=MYCLOUD_PUBLIC')
xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build build "${EXTRA[@]}" 2>&1 \
  | grep -E " error:|BUILD (SUCCEEDED|FAILED)"
[ -d "$APP" ] || { echo "build falhou"; exit 1; }

# Public build: Coucou's sounds stay out of the bundle (My Cloud's own are in cloud-sounds).
rm -rf "$APP/Contents/Resources/sounds"

# The Debug build loads "My Cloud.debug.dylib": it must carry the same signature as the app.
for lib in "$APP"/Contents/MacOS/*.dylib(N); do codesign --force --sign "$IDENTITY" "$lib"; done
codesign --force --deep --sign "$IDENTITY" --identifier com.gabrielreis.mycloud \
  --entitlements Resources/Coucou.entitlements --options runtime "$APP"
codesign -dv "$APP" 2>&1 | grep -E "^Identifier|^Authority" || true

INSTALLED="/Applications/My Cloud.app"
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"
rm -rf "$APP"
echo "instalado em $INSTALLED"
[ "${MYCLOUD_NO_OPEN:-}" = "1" ] || open "$INSTALLED"
