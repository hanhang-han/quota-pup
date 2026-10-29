#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
app_dir="$project_dir/build/余粮.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/Assets/sprites.json" "$app_dir/Contents/Resources/sprites.json"
cp "$project_dir/ThirdPartyNotices/CodexBar.txt" "$app_dir/Contents/Resources/CodexBar-MIT.txt"
python3 - "$project_dir" <<'PY'
import json
import sys
from pathlib import Path
project = Path(sys.argv[1])
sheet = json.loads((project / 'Assets/sprites.json').read_text())
assert (sheet['width'], sheet['height']) == (24, 18), 'Expected a 24 x 18 pixel grid'
assert {s['id'] for s in sheet['states']} == {'bright', 'steady', 'sit', 'rest', 'sleep'}
for state in sheet['states']:
    for rows in [state['rows']] + [frame['rows'] for frame in state['frames']]:
        assert len(rows) == 18 and all(len(row) == 24 for row in rows), state['id']
        assert set(''.join(rows)) <= set('.obce'), state['id']
    assert all(frame['durationMs'] >= 80 for frame in state['frames']), state['id']
template = (project / 'preview.template.html').read_text()
(project / 'preview.html').write_text(template.replace('__SPRITES__', json.dumps(sheet, ensure_ascii=False)))
PY
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>QuotaPup</string>
<key>CFBundleIdentifier</key><string>local.quotapup.prototype</string>
<key>CFBundleName</key><string>余粮</string>
<key>CFBundleDisplayName</key><string>余粮</string>
<key>CFBundleShortVersionString</key><string>0.4.1</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$project_dir/.build/module-cache"
target_arch="${QUOTAPUP_ARCH:-$(uname -m)}"
case "$target_arch" in
  arm64|x86_64) ;;
  *) echo "Unsupported architecture: $target_arch" >&2; exit 1 ;;
esac
xcrun swiftc -swift-version 5 -target "${target_arch}-apple-macosx14.0" -O -framework AppKit -module-cache-path "$project_dir/.build/module-cache" "$project_dir"/Sources/*.swift -o "$app_dir/Contents/MacOS/QuotaPup"
signing_identity="${QUOTAPUP_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
  codesign --force --sign - "$app_dir"
else
  codesign --force --sign "$signing_identity" --options runtime --timestamp "$app_dir"
fi
echo "$app_dir"
