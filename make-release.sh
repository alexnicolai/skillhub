#!/bin/zsh
# One-command release: build → sign → (notarize) → zip+dmg → EdDSA-sign →
# appcast → push → GitHub release. Users on Sparkle builds get the in-app
# "Update and Relaunch" prompt within a day (or on manual check).
#
# Usage: ./make-release.sh "Release notes markdown…"
#
# Prereqs:
#   - Bump SkillHub/AppVersion.swift first (the version IS the release).
#   - Sparkle EdDSA private key in login Keychain (generate_keys, done once).
#   - Optional but recommended: Developer ID cert in Keychain and a notary
#     profile: xcrun notarytool store-credentials skillhub-notary \
#       --apple-id you@example.com --team-id TEAMID --password app-specific-pw
set -euo pipefail
cd "$(dirname "$0")"

NOTES="${1:?usage: ./make-release.sh \"release notes\"}"
VERSION=$(grep 'static let current' SkillHub/AppVersion.swift | sed -E 's/.*"([^"]+)".*/\1/')
TAG="v${VERSION}"
SIGN_UPDATE=.build/artifacts/sparkle/Sparkle/bin/sign_update

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "✗ tag $TAG already exists — bump SkillHub/AppVersion.swift first"; exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "✗ working tree not clean — commit first"; exit 1
fi

echo "═══ Releasing SkillHub ${TAG} ═══"
./make-app.sh --dmg

# Notarize when credentials exist (makes first-install friction-free too).
if xcrun notarytool history --keychain-profile skillhub-notary >/dev/null 2>&1; then
  echo "→ Notarizing…"
  xcrun notarytool submit dist/SkillHub.dmg --keychain-profile skillhub-notary --wait
  xcrun stapler staple dist/SkillHub.dmg
  xcrun stapler staple dist/SkillHub.app
  echo "✓ Notarized"
else
  echo "⚠ No 'skillhub-notary' keychain profile — skipping notarization."
fi

# Sparkle update archive (zip is what Sparkle installs from).
ZIP="dist/SkillHub-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent dist/SkillHub.app "$ZIP"

echo "→ Signing update for Sparkle…"
ED_SIG=$("$SIGN_UPDATE" "$ZIP")   # → sparkle:edSignature="…" length="…"

echo "→ Writing appcast…"
DOWNLOAD_URL="https://github.com/alexnicolai/skillhub/releases/download/${TAG}/SkillHub-${VERSION}.zip"
PUBDATE=$(date -R)
cat > docs/appcast.xml <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SkillHub</title>
    <item>
      <title>SkillHub ${VERSION}</title>
      <link>https://github.com/alexnicolai/skillhub/releases/tag/${TAG}</link>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/alexnicolai/skillhub/releases/tag/${TAG}</sparkle:releaseNotesLink>
      <pubDate>${PUBDATE}</pubDate>
      <enclosure url="${DOWNLOAD_URL}" ${ED_SIG} type="application/octet-stream" />
    </item>
  </channel>
</rss>
APPCAST

echo "→ Publishing…"
git add docs/appcast.xml
git commit -m "release: ${TAG}"
git tag "$TAG"
git push origin main --tags
gh release create "$TAG" "$ZIP" dist/SkillHub.dmg \
  --title "SkillHub ${VERSION}" --notes "$NOTES"

echo ""
echo "✓ ${TAG} is live."
echo "  In-app updates go out via ${DOWNLOAD_URL}"
echo "  (appcast serves once GitHub Pages rebuilds — usually < 1 min)"
