#!/usr/bin/env bash
set -euo pipefail

# Builds ClaudeShot with SwiftPM, wraps the binary in a proper .app bundle
# (so Screen Recording permission sticks to the bundle id), ad-hoc signs it,
# and launches it.

MODE="${1:-run}"
APP_NAME="ClaudeShot"
BUNDLE_ID="com.mfuad.ClaudeShot"
MIN_SYSTEM_VERSION="14.0"
BUNDLE_VERSION="$(date +%Y%m%d%H%M%S)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${CLAUDESHOT_DIST_DIR:-${TMPDIR:-/tmp}/claudeshot-dist}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APPLICATIONS_BUNDLE="/Applications/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
cd "$ROOT_DIR"

swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>ClaudeShot</string>
  <key>CFBundleDisplayName</key>
  <string>ClaudeShot</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSScreenCaptureUsageDescription</key>
  <string>ClaudeShot uses ScreenCaptureKit only when you take an appshot, so it can paste the frontmost window into Claude.</string>
</dict>
</plist>
PLIST

/usr/bin/xattr -cr "$APP_BUNDLE" 2>/dev/null || true

SIGN_IDENTITY="${CLAUDESHOT_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
      | /usr/bin/awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }'
  )"
fi

sign_bundle() {
  local bundle="$1"
  if [[ -n "$SIGN_IDENTITY" ]]; then
    /usr/bin/codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$bundle"
  else
    /usr/bin/codesign --force --deep --sign - "$bundle"
  fi
}

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing with: $SIGN_IDENTITY"
else
  echo "No codesigning identity found; ad-hoc signing. Screen Recording/Accessibility permission may need re-granting after each rebuild." >&2
fi
sign_bundle "$APP_BUNDLE"

# Install into /Applications so macOS TCC will let you grant Screen Recording
# and Accessibility permissions (temp-dir apps can't be added, and vanish).
INSTALLED_BUNDLE="$APP_BUNDLE"
if [[ -d /Applications && -w /Applications ]]; then
  echo "Installing to $APPLICATIONS_BUNDLE"
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  rm -rf "$APPLICATIONS_BUNDLE"
  /usr/bin/ditto "$APP_BUNDLE" "$APPLICATIONS_BUNDLE"
  sign_bundle "$APPLICATIONS_BUNDLE"
  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
  "$LSREGISTER" -f "$APPLICATIONS_BUNDLE" >/dev/null 2>&1 || true
  # Drop any stale temp-dir registration so only /Applications is known.
  "$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true
  INSTALLED_BUNDLE="$APPLICATIONS_BUNDLE"
else
  echo "/Applications is not writable; leaving app in $APP_BUNDLE (permissions may not stick)." >&2
fi

open_app() { /usr/bin/open "$INSTALLED_BUNDLE"; }

case "$MODE" in
  run)
    open_app
    ;;
  --build|build)
    echo "Built: $INSTALLED_BUNDLE"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|build|logs|verify]" >&2
    exit 2
    ;;
esac
