#!/bin/bash
# Writes the Sparkle feed installed copies of From check every 8 hours, next to the update
# archive: <dir of the zip>/appcast.xml. The download URL is the archive's name under the
# folder of the app's SUFeedURL (this fork's Cloudflare R2 bucket, docs/release.md), so the
# feed and its archives always sit side by side. The archive is signed with this fork's
# EdDSA key: SPARKLE_PRIVATE_KEY (CI secret), or the "From" key in the login keychain
# (made once with vendor/sparkle/bin/generate_keys --account From).
#   scripts/appcast.sh <From-x.y.z-build.zip> [From.app] [release-notes.html]
# CRA_UPDATE_URL overrides the download URL (tests point it at a local server).
set -euo pipefail
cd "$(dirname "$0")/.."
ZIP="${1:?usage: scripts/appcast.sh <update.zip> [From.app] [release-notes.html]}"
APP="${2:-build/From.app}"
NOTES="${3:-}"
OUT="$(dirname "$ZIP")/appcast.xml"
SPARKLE_ACCOUNT="${CRA_SPARKLE_ACCOUNT:-From}"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
VERSION="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
MIN_OS="$(plist LSMinimumSystemVersion)"
if [ -n "${CRA_UPDATE_URL:-}" ]; then
  URL="$CRA_UPDATE_URL"
  FEED_URL="$URL"
else
  FEED_URL="$(plist SUFeedURL 2>/dev/null)" ||
    { echo "$APP has no SUFeedURL: build it with CRA_RELEASE=1 (scripts/release.sh)" >&2; exit 1; }
  URL="${FEED_URL%/*}/$(basename "$ZIP")"
fi

SIGN=vendor/sparkle/bin/sign_update
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  ENCLOSURE="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN" --ed-key-file - "$ZIP")"
else
  ENCLOSURE="$("$SIGN" --account "$SPARKLE_ACCOUNT" "$ZIP")"
fi

DESCRIPTION=""
if [ -n "$NOTES" ] && [ -f "$NOTES" ]; then
  DESCRIPTION="
      <description><![CDATA[$(cat "$NOTES")]]></description>"
fi

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>From</title>
    <link>$FEED_URL</link>
    <item>
      <title>From $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>$DESCRIPTION
      <enclosure url="$URL" type="application/octet-stream" $ENCLOSURE/>
    </item>
  </channel>
</rss>
XML
echo "Wrote $OUT (From $VERSION, build $BUILD)"
