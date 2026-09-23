#!/bin/bash

set -euo pipefail

readonly APP_NAME="Remote for Mac"
readonly SCHEME_NAME="RemoteForMac"
readonly TEAM_ID="${TEAM_ID:-9GALM9GLFA}"
readonly NOTARY_PROFILE="${NOTARY_PROFILE:-RemoteForMac}"
readonly SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
readonly SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-RemoteForMac}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT="$SCRIPT_DIR/RemoteForMac.xcodeproj"
readonly OUTPUT_DMG="$PROJECT_ROOT/web/public/App.dmg"
readonly OUTPUT_APPCAST="$PROJECT_ROOT/web/public/appcast.xml"
readonly SPM_CACHE_DIR="${SPM_CACHE_DIR:-$HOME/Library/Caches/RemoteForMac/SourcePackages}"
readonly WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/RemoteForMac-release.XXXXXX")"
readonly ARCHIVE="$WORK_DIR/RemoteForMac.xcarchive"
readonly EXPORT_DIR="$WORK_DIR/export"
readonly EXPORT_OPTIONS="$WORK_DIR/ExportOptions.plist"
readonly APPCAST_STAGING="$WORK_DIR/appcast"
readonly UNSIGNED_DMG="$WORK_DIR/$APP_NAME.dmg"
readonly NOTARY_RESULT="$WORK_DIR/notarization.json"
readonly DMG_VOLUME_NAME="Remote for Mac"
readonly DMG_WINDOW_WIDTH=700
readonly DMG_WINDOW_HEIGHT=480
readonly DMG_ICON_SIZE=128
readonly DMG_CONTENT_VERTICAL_OFFSET=35
readonly DMG_APP_ICON_X=150
readonly DMG_ICON_Y=$((DMG_WINDOW_HEIGHT / 2 - DMG_CONTENT_VERTICAL_OFFSET))
readonly DMG_APPLICATIONS_ICON_X=550
readonly DMG_WRITABLE_IMAGE="$WORK_DIR/$APP_NAME-rw.dmg"
readonly DMG_MOUNT_POINT="$WORK_DIR/$DMG_VOLUME_NAME"
readonly DMG_BACKGROUND="$WORK_DIR/dmg-background.png"
MOUNTED_DMG=0

cleanup() {
  if [[ "$MOUNTED_DMG" -eq 1 ]]; then
    hdiutil detach "$DMG_MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

for command in xcodebuild codesign hdiutil xcrun ditto osascript spctl swift; do
  if ! command -v "$command" >/dev/null; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

echo "Checking notarization credentials in keychain profile '$NOTARY_PROFILE'..."
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
  cat >&2 <<EOF
No working notarization profile named '$NOTARY_PROFILE' was found.
Create it once with:
  xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id "YOUR_APPLE_ID" --team-id "$TEAM_ID"
EOF
  exit 1
fi

echo "Resolving release dependencies..."
mkdir -p "$SPM_CACHE_DIR"
xcodebuild -resolvePackageDependencies \
  -project "$PROJECT" \
  -scheme "$SCHEME_NAME" \
  -clonedSourcePackagesDirPath "$SPM_CACHE_DIR"

readonly SPARKLE_BIN="$SPM_CACHE_DIR/artifacts/sparkle/Sparkle/bin"
readonly GENERATE_KEYS="$SPARKLE_BIN/generate_keys"
readonly GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"

if [[ ! -x "$GENERATE_KEYS" || ! -x "$GENERATE_APPCAST" ]]; then
  echo "Sparkle release tools were not found in $SPARKLE_BIN." >&2
  exit 1
fi

if ! SPARKLE_PUBLIC_KEY="$($GENERATE_KEYS --account "$SPARKLE_ACCOUNT" -p 2>/dev/null)"; then
  cat >&2 <<EOF
No Sparkle signing key named '$SPARKLE_ACCOUNT' was found.
Create it once with:
  "$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT"
EOF
  exit 1
fi
readonly SPARKLE_PUBLIC_KEY

echo "Archiving $APP_NAME with Hardened Runtime..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  -clonedSourcePackagesDirPath "$SPM_CACHE_DIR" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  ENABLE_HARDENED_RUNTIME=YES

cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>$SIGNING_IDENTITY</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
</dict>
</plist>
EOF

echo "Exporting Developer ID application..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

readonly APP="$EXPORT_DIR/$APP_NAME.app"

if [[ ! -d "$APP" ]]; then
  echo "Archive did not contain $APP_NAME.app." >&2
  exit 1
fi

readonly APP_INFO="$APP/Contents/Info.plist"
readonly RELEASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO")"
readonly BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_INFO")"
readonly EMBEDDED_SPARKLE_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP_INFO")"

if [[ "$EMBEDDED_SPARKLE_PUBLIC_KEY" != "$SPARKLE_PUBLIC_KEY" ]]; then
  echo "The archived app's SUPublicEDKey does not match Keychain account '$SPARKLE_ACCOUNT'." >&2
  exit 1
fi

echo "Verifying application signature..."
codesign --verify --deep --strict --verbose=2 "$APP"
APP_SIGNING_IDENTITY="$(codesign --display --verbose=4 "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p')"
readonly APP_SIGNING_IDENTITY

if [[ -z "$APP_SIGNING_IDENTITY" ]]; then
  echo "The archived app was not signed with a Developer ID Application certificate." >&2
  exit 1
fi

echo "Creating disk image..."
hdiutil create \
  -size 80m \
  -fs HFS+ \
  -volname "$DMG_VOLUME_NAME" \
  -ov \
  "$DMG_WRITABLE_IMAGE"
mkdir -p "$DMG_MOUNT_POINT"
hdiutil attach \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$DMG_MOUNT_POINT" \
  "$DMG_WRITABLE_IMAGE"
MOUNTED_DMG=1

mkdir -p "$DMG_MOUNT_POINT/.background"
ditto "$APP" "$DMG_MOUNT_POINT/$APP_NAME.app"
ln -s /Applications "$DMG_MOUNT_POINT/Applications"
swift "$SCRIPT_DIR/Scripts/RenderDMGBackground.swift" \
  "$DMG_BACKGROUND" \
  "$DMG_WINDOW_WIDTH" \
  "$DMG_WINDOW_HEIGHT" \
  "$DMG_CONTENT_VERTICAL_OFFSET"
ditto "$DMG_BACKGROUND" "$DMG_MOUNT_POINT/.background/background.png"

osascript <<EOF
tell application "Finder"
  tell disk "$DMG_VOLUME_NAME"
    open
    set layoutWindow to container window
    set current view of layoutWindow to icon view
    set toolbar visible of layoutWindow to false
    set statusbar visible of layoutWindow to false
    set bounds of layoutWindow to {100, 100, $((100 + DMG_WINDOW_WIDTH)), $((100 + DMG_WINDOW_HEIGHT))}
    set viewOptions to icon view options of layoutWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $DMG_ICON_SIZE
    set text size of viewOptions to 10
    set shows item info of viewOptions to false
    set shows icon preview of viewOptions to true
    set background picture of viewOptions to (POSIX file "$DMG_MOUNT_POINT/.background/background.png" as alias)
    set position of item "$APP_NAME.app" to {$DMG_APP_ICON_X, $DMG_ICON_Y}
    set position of item "Applications" to {$DMG_APPLICATIONS_ICON_X, $DMG_ICON_Y}
    close layoutWindow
  end tell
end tell
EOF

sync
hdiutil detach "$DMG_MOUNT_POINT"
MOUNTED_DMG=0
hdiutil convert \
  "$DMG_WRITABLE_IMAGE" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$UNSIGNED_DMG"

echo "Signing disk image..."
codesign --force --timestamp --sign "$APP_SIGNING_IDENTITY" "$UNSIGNED_DMG"

echo "Submitting disk image for notarization..."
xcrun notarytool submit "$UNSIGNED_DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json > "$NOTARY_RESULT"
cat "$NOTARY_RESULT"

if [[ "$(plutil -extract status raw -o - "$NOTARY_RESULT")" != "Accepted" ]]; then
  echo "Apple rejected the notarization submission." >&2
  exit 1
fi

echo "Stapling and validating notarization ticket..."
xcrun stapler staple "$UNSIGNED_DMG"
xcrun stapler validate "$UNSIGNED_DMG"
codesign --verify --verbose=2 "$UNSIGNED_DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$UNSIGNED_DMG"

mkdir -p "$(dirname "$OUTPUT_DMG")"
cp "$UNSIGNED_DMG" "$OUTPUT_DMG.tmp"
mv "$OUTPUT_DMG.tmp" "$OUTPUT_DMG"
codesign --verify --verbose=2 "$OUTPUT_DMG"
xcrun stapler validate "$OUTPUT_DMG"

echo "Generating signed Sparkle appcast for version $RELEASE_VERSION ($BUILD_VERSION)..."
mkdir -p "$APPCAST_STAGING"
cp "$OUTPUT_DMG" "$APPCAST_STAGING/App.dmg"
"$GENERATE_APPCAST" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "https://remote-for-mac.vercel.app/" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  -o "$APPCAST_STAGING/appcast.xml" \
  "$APPCAST_STAGING"

mkdir -p "$(dirname "$OUTPUT_APPCAST")"
cp "$APPCAST_STAGING/appcast.xml" "$OUTPUT_APPCAST.tmp"
mv "$OUTPUT_APPCAST.tmp" "$OUTPUT_APPCAST"

codesign --verify --verbose=2 "$OUTPUT_DMG"
xcrun stapler validate "$OUTPUT_DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$OUTPUT_DMG"

echo "Created notarized release: $OUTPUT_DMG"
echo "Updated signed appcast: $OUTPUT_APPCAST"
echo "Commit the updated DMG and appcast, then deploy the web project."
