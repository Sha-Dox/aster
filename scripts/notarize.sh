#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool Keychain profile}"
app_path="${1:-../Aster.app}"
# Requires a Developer ID release; Apple Development and ad-hoc signatures cannot be notarized.
codesign --verify --deep "$app_path"
staging_dir="$(mktemp -d /private/tmp/aster-notarize.XXXXXX)"
archive_path="$staging_dir/Aster.zip"
trap 'rm -rf "$staging_dir"' EXIT
ditto --norsrc --noextattr -c -k --keepParent "$app_path" "$archive_path"
xcrun notarytool submit "$archive_path" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose "$app_path"
