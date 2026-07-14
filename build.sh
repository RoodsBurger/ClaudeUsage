#!/usr/bin/env bash
# Build RaiUsage (Release), install it to /Applications, and launch it.
# Local builds are ad-hoc signed and not notarized; built on this machine they
# carry no quarantine flag, so macOS opens them directly. If Gatekeeper ever
# complains, right-click the app > Open once.
set -euo pipefail

cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"

APP="RaiUsage.app"
CONFIG="Release"
DERIVED="build"
DEST="/Applications/$APP"

# 1. Xcode check
if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
  echo "error: building from source requires Xcode.app (App Store), then:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  echo "" >&2
  echo "No Xcode? Download the prebuilt DMG instead:" >&2
  echo "  https://github.com/RoodsBurger/RaiUsage/releases/latest" >&2
  exit 1
fi

# 2. XcodeGen check
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Installing XcodeGen via Homebrew"
  brew install xcodegen
fi

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building $CONFIG"
xcodebuild \
  -project TokenEater.xcodeproj \
  -scheme TokenEaterApp \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tail -3

BUILT="$DERIVED/Build/Products/$CONFIG/$APP"
if [ ! -d "$BUILT" ]; then
  echo "error: build product not found at $BUILT" >&2
  exit 1
fi

echo "==> Installing to /Applications"
killall RaiUsage 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"
xattr -cr "$DEST"

# Xcode registers the build product with LaunchServices during the build,
# which shows up as a duplicate app in Spotlight/Launchpad. Unregister and
# remove it so /Applications holds the only copy.
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
"$LSREG" -u "$(cd "$(dirname "$BUILT")" && pwd)/$APP" 2>/dev/null || true
rm -rf "$BUILT"

echo "==> Launching"
open "$DEST"
echo "==> Done."
