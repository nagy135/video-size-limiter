#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="$PWD/build/Video Size Limiter.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
bin_dir="$(swift build -c release --show-bin-path)"
cp "$bin_dir/VideoSizeLimiter" "$app/Contents/MacOS/VideoSizeLimiter"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VideoSizeLimiter</string>
<key>CFBundleIdentifier</key><string>tech.infiniter.video-size-limiter</string>
<key>CFBundleName</key><string>Video Size Limiter</string>
<key>CFBundleDisplayName</key><string>Video Size Limiter</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSApplicationCategoryType</key><string>public.app-category.video</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Video</string>
<key>LSItemContentTypes</key><array><string>public.movie</string><string>public.video</string></array>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
</dict></array>
</dict></plist>
PLIST
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
