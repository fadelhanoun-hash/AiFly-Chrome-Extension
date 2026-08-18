#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_name="AiFly.app"
bundle_id="com.fadelhanoun.aifly"
# Use the certificate fingerprint because an older revoked certificate has the
# same display name in the login keychain.
signing_identity="28690C1B7AD97C72BF6DAE7B929B0846423B0E8B"
staging_dir="$(mktemp -d)"
staged_app="$staging_dir/$app_name"
installed_app="/Applications/$app_name"
exported_app="/Users/fadelhanoun/Downloads/$app_name"

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

cd "$project_dir"
swift build -c release

mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp ".build/release/AiFlyMac" "$staged_app/Contents/MacOS/AiFlyMac"
cp "Resources/Info.plist" "$staged_app/Contents/Info.plist"
cp "Resources/AiFlyIcon.icns" "$staged_app/Contents/Resources/AiFlyIcon.icns"

codesign --force --deep --options runtime --sign "$signing_identity" \
    --identifier "$bundle_id" "$staged_app"
codesign --verify --deep --strict "$staged_app"

pkill -f "/Applications/AiFly.app/Contents/MacOS/AiFlyMac" 2>/dev/null || true
ditto "$staged_app" "$installed_app"
ditto "$staged_app" "$exported_app"

launchctl bootout "gui/$(id -u)/com.fadelhanoun.aifly" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" \
    "/Users/fadelhanoun/Library/LaunchAgents/com.fadelhanoun.aifly.plist"

codesign --verify --deep --strict "$installed_app"
echo "Installed $installed_app and exported $exported_app"
