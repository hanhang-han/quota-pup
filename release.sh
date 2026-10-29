#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
if [[ "${QUOTAPUP_SIGNING_IDENTITY:-}" != "Developer ID Application:"* ]]; then
  echo 'Set QUOTAPUP_SIGNING_IDENTITY to a Developer ID Application identity.' >&2
  exit 1
fi
: "${QUOTAPUP_NOTARY_PROFILE:?Set QUOTAPUP_NOTARY_PROFILE to a configured notarytool Keychain profile.}"
"$project_dir/build.sh"
"$project_dir/test.sh"
app_dir="$project_dir/build/余粮.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
target_arch="${QUOTAPUP_ARCH:-$(uname -m)}"
release_dir="$project_dir/build/release"
archive_name="QuotaPup-v${version}-macos-${target_arch}.zip"
mkdir -p "$release_dir"
codesign --verify --deep --strict "$app_dir"
notary_dir="$project_dir/build/notarization"
mkdir -p "$notary_dir"
submission="$notary_dir/QuotaPup-v${version}-submission.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$submission"
xcrun notarytool submit "$submission" --keychain-profile "$QUOTAPUP_NOTARY_PROFILE" \
  --wait --timeout 30m --output-format json > "$notary_dir/result.json"
python3 - "$notary_dir/result.json" <<'PY'
import json
import sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple notarization was not Accepted; no distributable archive was created.')
print('Apple notarization: Accepted')
PY
xcrun stapler staple "$app_dir"
xcrun stapler validate "$app_dir"
spctl --assess --type execute --verbose=2 "$app_dir"
# Only package the app after its notarization ticket has been stapled.
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$release_dir/$archive_name"
(
  cd "$release_dir"
  shasum -a 256 "$archive_name" > SHA256SUMS.txt
)
echo "$release_dir/$archive_name"
