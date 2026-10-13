#!/bin/zsh
# Publishes My Cloud as a ready-made app on GitHub Releases (gabrielxreis/myclaude), so installing
# and the daily update need no Xcode: exports the public copy, builds it (MYCLOUD_PUBLIC), signs it
# with the stable local identity, zips it and creates a release with MyCloud.zip.
#
#   scripts/publicar-release.sh            (from the personal fork)
set -e
FORK="$(cd "$(dirname "$0")/.." && pwd)"
PUB="${MYCLOUD_PUBLIC_DIR:-$HOME/Documents/myclaude}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 "$FORK/scripts/exportar-publico.py" "$PUB" >/dev/null
cd "$PUB"
git add -A
git diff --cached --quiet || git commit -q -m "My Cloud $(date +%Y.%m.%d)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -q origin main

cd "$PUB/NotchBuddy"
xcodegen >/dev/null
xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath "$WORK/build" build \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=MYCLOUD_PUBLIC' 2>&1 | grep -E " error:|BUILD (SUCCEEDED|FAILED)"
rm -rf NotchBuddy.xcodeproj
APP="$WORK/build/Build/Products/Debug/My Cloud.app"
[ -d "$APP" ] || { echo "build falhou"; exit 1; }
rm -rf "$APP/Contents/Resources/sounds"

VERSION="$(date -u +%Y.%m.%d-%H%M)"
/usr/libexec/PlistBuddy -c "Add :MyCloudBuildDate string $(date -u +%Y-%m-%dT%H:%M:%SZ)" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :MyCloudBuildDate $(date -u +%Y-%m-%dT%H:%M:%SZ)" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"

IDENTITY="${MYCLOUD_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/{print $2; exit}')}"
[ -n "$IDENTITY" ] || IDENTITY="-"
for lib in "$APP"/Contents/MacOS/*.dylib(N); do codesign --force --sign "$IDENTITY" "$lib"; done
codesign --force --deep --sign "$IDENTITY" --identifier com.gabrielreis.mycloud \
  --entitlements Resources/Coucou.entitlements --options runtime "$APP"

ditto -c -k --keepParent "$APP" "$WORK/MyCloud.zip"
cd "$PUB"
gh release create "v$VERSION" "$WORK/MyCloud.zip" --repo gabrielxreis/myclaude --title "My Cloud $VERSION" \
  --notes "App pronto: o instalador e a atualização automática baixam este MyCloud.zip (não precisa de Xcode)."
echo "publicado: v$VERSION"
