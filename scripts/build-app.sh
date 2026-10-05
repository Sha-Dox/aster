#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
staging_dir="$(mktemp -d /private/tmp/aster-build.XXXXXX)"
trap 'rm -rf "$staging_dir"' EXIT
app_path="$staging_dir/Aster.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Frameworks" "$app_path/Contents/Resources"
cp "$binary_dir/Aster" "$app_path/Contents/MacOS/Aster"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
if [[ -f Resources/Aster.icns ]]; then cp Resources/Aster.icns "$app_path/Contents/Resources/"; fi
for resource in "$binary_dir"/*.bundle(N); do ditto "$resource" "$app_path/Contents/Resources/$(basename "$resource")"; done
cp Resources/PrivacyInfo.xcprivacy "$app_path/Contents/Resources/"
cp THIRD_PARTY_NOTICES.md "$app_path/Contents/Resources/"
ditto "$binary_dir/MSAL.framework" "$app_path/Contents/Frameworks/MSAL.framework"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$app_path/Contents/MacOS/Aster"
# Developer ID signing is required for distribution and reliable MSAL Keychain persistence.
# Local builds use an ad-hoc signature; set SIGNING_IDENTITY for a stable developer identity.
chmod -R u+w "$app_path"
xattr -cr "$app_path"
signing_identity="${SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
  codesign --force --sign - "$app_path/Contents/Frameworks/MSAL.framework"
  codesign --force --sign - "$app_path"
else
  codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_path/Contents/Frameworks/MSAL.framework"
  codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_path"
fi
codesign --verify --deep --strict "$app_path"
ditto --norsrc --noextattr "$app_path" "../Aster.app"
printf 'Built ../Aster.app\n'
