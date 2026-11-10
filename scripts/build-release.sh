#!/usr/bin/env bash
# Builds, signs and notarizes Hotline Capture on a Mac. Apple Silicon only.
# NOT YET TRIED: written without a Mac. Run it by hand first, never from a pull request.
#
# Needs in the environment (never in files): DEVELOPMENT_TEAM, APPLE_ID, APPLE_APP_PASSWORD,
# and the Developer ID certificate and the two provisioning profiles already installed.
set -euo pipefail

: "${DEVELOPMENT_TEAM:?set your Apple team id}"
: "${APPLE_ID:?set your Apple id}"
: "${APPLE_APP_PASSWORD:?set an app-specific password}"

cd "$(dirname "$0")/.."
xcodegen
rm -rf build dist && mkdir -p build dist

xcodebuild -scheme HotlineCapture -configuration Release \
  -archivePath build/HotlineCapture.xcarchive \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" archive
xcodebuild -exportArchive -archivePath build/HotlineCapture.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath build

APP="build/Hotline Capture.app"
ditto -c -k --keepParent "$APP" build/HotlineCapture.zip
xcrun notarytool submit build/HotlineCapture.zip \
  --apple-id "$APPLE_ID" --team-id "$DEVELOPMENT_TEAM" --password "$APPLE_APP_PASSWORD" --wait
xcrun stapler staple "$APP"

tar --create --file dist/HotlineCapture.app.tar --cd build "Hotline Capture.app"
shasum -a 256 dist/HotlineCapture.app.tar > dist/HotlineCapture.app.tar.sha256
echo "Done: dist/HotlineCapture.app.tar and its checksum."
