#!/bin/zsh
# Builds SkillHub.app (product display name: Skill Library) from the Swift
# package (release) into dist/. Binary, bundle id, and .app basename stay
# SkillHub for Sparkle continuity and CLI muscle memory.
# Usage: ./make-app.sh [--install|--dmg]
#   --install  copies to /Applications
#   --dmg      also builds dist/SkillHub.dmg (drag-to-Applications)
#
# Signing: uses a "Developer ID Application" identity when available
# (required for notarization + friction-free Gatekeeper), else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(grep 'static let current' SkillHub/AppVersion.swift | sed -E 's/.*"([^"]+)".*/\1/')
PUBLIC_ED_KEY=$(cat sparkle_public_key.txt)
APPCAST_URL="https://alexnicolai.github.io/skillhub/appcast.xml"

echo "→ Building release (v${VERSION})…"
swift build -c release

APP=dist/SkillHub.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/SkillHub "$APP/Contents/MacOS/SkillHub"

# Embed Sparkle (linked as @rpath/…; rpath @executable_path/../Frameworks is
# set in Package.swift linkerSettings).
SPARKLE_FW=.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"

# SPM resource bundles (app resources + MarkdownUI). Bundle.module checks
# Bundle.main.resourceURL, which is Contents/Resources inside an app bundle.
for bundle in .build/release/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

# App icon (generated; rebuild when source is newer than the cache).
if [[ ! -f dist/AppIcon.icns || AppIcon-source.png -nt dist/AppIcon.icns ]]; then
  echo "→ Rendering app icon…"
  rm -rf dist/AppIcon.iconset dist/AppIcon.icns
  swift make-icon.swift
  iconutil -c icns dist/AppIcon.iconset -o dist/AppIcon.icns
  rm -rf dist/AppIcon.iconset
fi
cp dist/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Compile the asset catalog: AccentColor drives system selection highlights
# and controls app-wide via NSAccentColorName.
xcrun actool Assets.xcassets --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 \
  --output-partial-info-plist /dev/null >/dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>SkillHub</string>
    <key>CFBundleIdentifier</key>          <string>com.alexnicolai.skillhub</string>
    <key>CFBundleName</key>                <string>Skill Library</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>CFBundleDisplayName</key>         <string>Skill Library</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>${VERSION}</string>
    <key>CFBundleVersion</key>             <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>LSApplicationCategoryType</key>   <string>public.app-category.developer-tools</string>
    <key>SUFeedURL</key>                   <string>${APPCAST_URL}</string>
    <key>SUPublicEDKey</key>               <string>${PUBLIC_ED_KEY}</string>
    <key>SUEnableAutomaticChecks</key>     <true/>
    <key>NSAccentColorName</key>           <string>AccentColor</string>
</dict>
</plist>
PLIST

# Prefer Developer ID for distribution; fall back to ad-hoc.
# Sign by SHA-1 hash: duplicate same-name certs make name-based signing ambiguous.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | awk '{print $2}' || true)
if [[ -n "$IDENTITY" ]]; then
  echo "→ Signing with: $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  echo "→ No Developer ID identity found — ad-hoc signing (right-click → Open on first launch)."
  codesign --force --deep --sign - "$APP"
fi
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
  cp -R "$APP" "$STAGING/Skill Library.app"   # brand-named for the drag-install
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "Skill Library" -srcfolder "$STAGING" -ov -format UDZO \
    -fs HFS+ dist/SkillHub.dmg >/dev/null
  rm -rf "$STAGING"
  echo "✓ Built dist/SkillHub.dmg ($(du -h dist/SkillHub.dmg | cut -f1 | tr -d ' '))"
fi
