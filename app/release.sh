#!/bin/bash

set -euo pipefail

readonly APP_NAME="Remote for Mac"
readonly SCHEME_NAME="RemoteForMac"
readonly TEAM_ID="${TEAM_ID:-9GALM9GLFA}"
readonly NOTARY_PROFILE="${NOTARY_PROFILE:-RemoteForMac}"
readonly SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT="$SCRIPT_DIR/RemoteForMac.xcodeproj"
readonly OUTPUT_DMG="$PROJECT_ROOT/$APP_NAME.dmg"
readonly WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/RemoteForMac-release.XXXXXX")"
readonly ARCHIVE="$WORK_DIR/RemoteForMac.xcarchive"
readonly STAGING="$WORK_DIR/dmg"
readonly UNSIGNED_DMG="$WORK_DIR/$APP_NAME.dmg"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

for command in xcodebuild codesign hdiutil xcrun ditto spctl; do
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

echo "Archiving $APP_NAME with Hardened Runtime..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  ENABLE_HARDENED_RUNTIME=YES

readonly APP="$ARCHIVE/Products/Applications/$APP_NAME.app"

if [[ ! -d "$APP" ]]; then
  echo "Archive did not contain $APP_NAME.app." >&2
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
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create \
  -volname "Remote for Mac" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -ov \
  "$UNSIGNED_DMG"

echo "Signing disk image..."
codesign --force --timestamp --sign "$APP_SIGNING_IDENTITY" "$UNSIGNED_DMG"

echo "Submitting disk image for notarization..."
xcrun notarytool submit "$UNSIGNED_DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "Stapling and validating notarization ticket..."
xcrun stapler staple "$UNSIGNED_DMG"
xcrun stapler validate "$UNSIGNED_DMG"
codesign --verify --verbose=2 "$UNSIGNED_DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$UNSIGNED_DMG"

rm -f "$OUTPUT_DMG"
mv "$UNSIGNED_DMG" "$OUTPUT_DMG"

echo "Created notarized release: $OUTPUT_DMG"
