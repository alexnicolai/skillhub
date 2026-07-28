#!/bin/zsh
# Builds SkillHub.app from the Swift package (release) into app/dist/.
# Usage: ./make-app.sh [--install]   (--install copies to /Applications)
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(grep 'static let current' SkillHub/AppVersion.swift | sed -E 's/.*"([^"]+)".*/\1/')

echo "→ Building release…"
swift build -c release

APP=dist/SkillHub.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/SkillHub "$APP/Contents/MacOS/SkillHub"

# SPM resource bundles (app resources + MarkdownUI). Bundle.module checks
# Bundle.main.resourceURL, which is Contents/Resources inside an app bundle.
for bundle in .build/release/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

# App icon (generated; cached across builds).
if [[ ! -f dist/AppIcon.icns ]]; then
  echo "→ Rendering app icon…"
  swift make-icon.swift
  iconutil -c icns dist/AppIcon.iconset -o dist/AppIcon.icns
  rm -rf dist/AppIcon.iconset
fi
cp dist/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>SkillHub</string>
    <key>CFBundleIdentifier</key>          <string>com.alexnicolai.skillhub</string>
    <key>CFBundleName</key>                <string>SkillHub</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>CFBundleDisplayName</key>         <string>SkillHub</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>${VERSION}</string>
    <key>CFBundleVersion</key>             <string>1</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>LSApplicationCategoryType</key>   <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/SkillHub.app
  cp -R "$APP" /Applications/SkillHub.app
  echo "✓ Installed to /Applications/SkillHub.app"
fi

if [[ "${1:-}" == "--dmg" ]]; then
  echo "→ Building DMG…"
  STAGING=dist/dmg-staging
  rm -rf "$STAGING" dist/SkillHub.dmg
  mkdir -p "$STAGING"
  cp -R "$APP" "$STAGING/SkillHub.app"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "SkillHub" -srcfolder "$STAGING" -ov -format UDZO \
    -fs HFS+ dist/SkillHub.dmg >/dev/null
  rm -rf "$STAGING"
  echo "✓ Built dist/SkillHub.dmg ($(du -h dist/SkillHub.dmg | cut -f1 | tr -d ' '))"
fi
