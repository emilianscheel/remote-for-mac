#!/bin/bash

set -euo pipefail

readonly APP_NAME="RemoteForMac"
readonly TEAM_ID="${TEAM_ID:-9GALM9GLFA}"
readonly NOTARY_PROFILE="${NOTARY_PROFILE:-RemoteForMac}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT="$SCRIPT_DIR/RemoteForMac.xcodeproj"
readonly OUTPUT_DMG="$PROJECT_ROOT/RemoteForMac.dmg"
readonly WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/RemoteForMac-release.XXXXXX")"
readonly ARCHIVE="$WORK_DIR/RemoteForMac.xcarchive"
readonly STAGING="$WORK_DIR/dmg"
readonly UNSIGNED_DMG="$WORK_DIR/RemoteForMac.dmg"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

for command in xcodebuild codesign hdiutil xcrun security ditto spctl; do
  if ! command -v "$command" >/dev/null; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' -v team="($TEAM_ID)" 'index($0, "Developer ID Application:") && index($0, team) && !found { identity=$2; found=1 } END { if (found) print identity }')"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  cat >&2 <<EOF
No Developer ID Application certificate was found for team $TEAM_ID.
Create one in Xcode > Settings > Accounts > Manage Certificates, then run this script again.
EOF
  exit 1
fi

echo "Checking notarization credentials in keychain profile '$NOTARY_PROFILE'..."
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
  cat >&2 <<EOF
No working notarization profile named '$NOTARY_PROFILE' was found.
Create it once with:
  xcrun notarytool store-credentials "$NOTARY_PROFILE" --team-id "$TEAM_ID"
EOF
  exit 1
fi

echo "Archiving $APP_NAME with Hardened Runtime..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
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
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$UNSIGNED_DMG"

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
