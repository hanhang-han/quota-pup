#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
"$project_dir/build.sh"
"$project_dir/test.sh"
app_dir="$project_dir/build/余粮.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
target_arch="${QUOTAPUP_ARCH:-$(uname -m)}"
release_dir="$project_dir/build/release"
archive_name="QuotaPup-v${version}-macos-${target_arch}.zip"
mkdir -p "$release_dir"
codesign --verify --deep --strict "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$release_dir/$archive_name"
(
  cd "$release_dir"
  shasum -a 256 "$archive_name" > SHA256SUMS.txt
)
echo "$release_dir/$archive_name"
