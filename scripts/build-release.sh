#!/usr/bin/env bash
# Builds, signs and notarizes Hotline Capture. Apple Silicon only.
# Runs in CI (.github/workflows/release.yml) or on a Mac. Never tried end to end yet.
#
# Needs in the environment (never in files):
#   DEVELOPMENT_TEAM       Apple team id
#   APPLE_ID               Apple id used for notarizing
#   APPLE_APP_PASSWORD     app-specific password for that Apple id
# Also needs the Developer ID certificate in a keychain that is unlocked and searchable,
# and the two provisioning profiles installed (the CI workflow does both).
# Optional: VERSION (for example 0.1.0) and BUILD_NUMBER (must rise with every release).
set -euo pipefail

: "${DEVELOPMENT_TEAM:?set your Apple team id}"
: "${APPLE_ID:?set your Apple id}"
: "${APPLE_APP_PASSWORD:?set an app-specific password}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

cd "$(dirname "$0")/.."
xcodegen
rm -rf build dist && mkdir -p build dist

# The export step needs to know which profile belongs to which part.
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${DEVELOPMENT_TEAM}</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>destination</key>
	<string>export</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>io.github.petercipov.hotlinecapture</key>
		<string>Hotline Capture</string>
		<key>io.github.petercipov.hotlinecapture.extension</key>
		<string>Hotline Capture Extension</string>
	</dict>
</dict>
</plist>
PLIST

xcodebuild -scheme HotlineCapture -configuration Release \
  -archivePath build/HotlineCapture.xcarchive \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive
xcodebuild -exportArchive -archivePath build/HotlineCapture.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build

APP="build/Hotline Capture.app"
EXTENSION="$APP/Contents/Library/SystemExtensions/io.github.petercipov.hotlinecapture.extension.systemextension"

# Stop before notarizing if the signed app lacks what macOS needs to install the extension.
# The first release shipped with none of these and macOS refused it.
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "com.apple.developer.system-extension.install" \
  || { echo "The signed app has no system-extension.install entitlement." >&2; exit 1; }
codesign -d --entitlements :- "$EXTENSION" 2>/dev/null | grep -q "app-proxy-provider-systemextension" \
  || { echo "The signed extension has no app-proxy-provider-systemextension entitlement." >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Print :NetworkExtension:NEProviderClasses" "$EXTENSION/Contents/Info.plist" >/dev/null \
  || { echo "The extension's Info.plist has no NetworkExtension keys." >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Print :NSSystemExtensionUsageDescription" "$EXTENSION/Contents/Info.plist" >/dev/null \
  || { echo "The extension's Info.plist has no usage description." >&2; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")" = "$VERSION" ] \
  || { echo "The app's version is not $VERSION." >&2; exit 1; }

ditto -c -k --keepParent "$APP" build/HotlineCapture.zip
xcrun notarytool submit build/HotlineCapture.zip \
  --apple-id "$APPLE_ID" --team-id "$DEVELOPMENT_TEAM" --password "$APPLE_APP_PASSWORD" --wait
xcrun stapler staple "$APP"

# Check what we are about to ship before packing it.
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP"

tar --create --file dist/HotlineCapture.app.tar --cd build "Hotline Capture.app"
(cd dist && shasum -a 256 HotlineCapture.app.tar > HotlineCapture.app.tar.sha256)
# The software bill of materials: a list of what is inside the app, in the CycloneDX format.
# There are no third-party libraries, only Apple's own frameworks, so the list is short and written by hand.
cat > dist/HotlineCapture.sbom.cdx.json <<SBOM
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "version": 1,
  "metadata": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "component": {
      "type": "application",
      "bom-ref": "hotline-capture",
      "name": "Hotline Capture",
      "version": "${VERSION}",
      "purl": "pkg:github/petercipov/hotline-macos-capture@v${VERSION}",
      "licenses": [{ "license": { "id": "Apache-2.0" } }]
    },
    "tools": { "components": [
      { "type": "application", "name": "xcodegen", "version": "$(xcodegen --version | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)", "description": "Build time only, not shipped" }
    ] }
  },
  "components": [
    { "type": "library", "bom-ref": "extension", "name": "io.github.petercipov.hotlinecapture.extension", "version": "${VERSION}", "description": "System extension inside the app" },
    { "type": "framework", "name": "Foundation", "description": "Apple system framework, not bundled" },
    { "type": "framework", "name": "Network", "description": "Apple system framework, not bundled" },
    { "type": "framework", "name": "NetworkExtension", "description": "Apple system framework, not bundled" }
  ],
  "dependencies": [
    { "ref": "hotline-capture", "dependsOn": ["extension"] }
  ]
}
SBOM
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' dist/HotlineCapture.sbom.cdx.json
(cd dist && shasum -a 256 HotlineCapture.sbom.cdx.json >> HotlineCapture.app.tar.sha256)
echo "Done: dist/HotlineCapture.app.tar, the SBOM and their checksums."
