#!/usr/bin/env bash
#
# RaiUsage installer — downloads the latest release DMG and installs the app to
# /Applications, then launches it. Because curl (unlike a browser) does not tag
# the download with com.apple.quarantine, Gatekeeper does not show the
# "Apple could not verify..." prompt: no manual "Open Anyway" step.
#
#   curl -fsSL https://raw.githubusercontent.com/RoodsBurger/RaiUsage/main/install.sh | bash
#
set -euo pipefail

REPO="RoodsBurger/RaiUsage"
APP="RaiUsage.app"
API="https://api.github.com/repos/${REPO}/releases/latest"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31mx\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "RaiUsage is macOS only."

say "Finding the latest RaiUsage release..."
# Pull the release JSON and pick the .dmg asset's download URL (no jq dependency).
RELEASE_JSON="$(curl -fsSL "$API" 2>/dev/null || true)"
[ -n "$RELEASE_JSON" ] || die "Could not reach GitHub. Check your connection and try again."

DMG_URL="$(printf '%s' "$RELEASE_JSON" \
  | grep -o '"browser_download_url": *"[^"]*\.dmg"' \
  | head -1 \
  | sed 's/.*"browser_download_url": *"\([^"]*\)"/\1/')"

if [ -z "$DMG_URL" ]; then
  if printf '%s' "$RELEASE_JSON" | grep -q 'API rate limit exceeded'; then
    die "GitHub rate limit hit (shared network?). Wait a bit, or download the DMG from https://github.com/${REPO}/releases/latest"
  fi
  die "No DMG found in the latest release. See https://github.com/${REPO}/releases/latest"
fi

TAG="$(printf '%s' "$RELEASE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)"/\1/')"
say "Downloading RaiUsage ${TAG:-latest}..."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; [ -n "${MOUNT:-}" ] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true' EXIT
DMG="$WORK/RaiUsage.dmg"
curl -fL# "$DMG_URL" -o "$DMG" || die "Download failed."

say "Mounting the disk image..."
MOUNT="$(hdiutil attach -nobrowser -noverify -noautoopen "$DMG" | grep -o '/Volumes/[^ ]*.*' | tail -1)"
[ -n "$MOUNT" ] && [ -d "$MOUNT/$APP" ] || die "Could not find $APP inside the DMG."

say "Installing to /Applications..."
# Replace any running copy: quit it first so the binary isn't held in memory.
osascript -e 'tell application "RaiUsage" to quit' 2>/dev/null || true
killall RaiUsage 2>/dev/null || true
rm -rf "/Applications/$APP"
cp -R "$MOUNT/$APP" /Applications/
hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
MOUNT=""

# Defensive: strip quarantine in case a proxy/AV added it, so the first launch
# is prompt-free even on locked-down networks.
xattr -cr "/Applications/$APP" 2>/dev/null || true
# Re-register with LaunchServices so macOS reads the fresh version metadata.
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f "/Applications/$APP" 2>/dev/null || true

say "Launching RaiUsage..."
open "/Applications/$APP"

printf '\033[1;32m✓ Installed RaiUsage %s.\033[0m It lives in your menu bar (no Dock icon).\n' "${TAG:-}"
