#!/bin/bash
# Full distributable build and Sparkle update: build, sign with Developer ID, notarize,
# package (zip, DMG), write the appcast for this fork's own feed and, with --publish,
# upload the update to Cloudflare R2.
#   scripts/release.sh --version 2.0.0 [--build-number N] [--notes notes.html]
#                      [--skip-notarization] [--publish]
# Without --publish nothing leaves the Mac: the update sits in build/dist/update/
# (From-<version>-<build>.zip and appcast.xml), the first-install DMG in build/dist/.
# --publish uploads the archive, then the appcast, to the R2 bucket behind SUFeedURL
# (resources/Info.plist), checks both are publicly reachable and keeps the newest
# RETAIN_VERSIONS archives. Installed copies then update within 8 hours.
#
# Secrets are never written to the repo:
# - the Sparkle EdDSA private key is in the login keychain (account CRA_SPARKLE_ACCOUNT,
#   default "From"), or SPARKLE_PRIVATE_KEY on CI;
# - notarization uses the notarytool keychain profile CRA_NOTARY_PROFILE (default
#   NoType-Notarization, the team's profile shared with NoType; made with
#   `xcrun notarytool store-credentials <name>`), or
#   APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD on CI;
# - R2 credentials (R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY) are read at run
#   time from CRA_R2_ENV_FILE (default ~/Develop/celia/apps/server/.env.production).
#
# Environment: CRA_SIGN_IDENTITY (default this fork's Developer ID), CRA_ARCHS (default
# arm64; the feed is Apple silicon only, an x86_64 build is packaged but gets no feed),
# CRA_R2_BUCKET (default from-updates), CRA_ALLOW_OLD_CEF=1 (see docs/release.md).
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf 'error: %s\n' "$1" >&2; exit 1; }
log() { printf '\n==> %s\n' "$1"; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }

VERSION="${CRA_VERSION:-}"
BUILD_NUMBER="${CRA_BUILD:-$(date -u +%Y%m%d%H%M)}"
NOTES=""
SKIP_NOTARIZATION=0
PUBLISH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?--build-number needs a value}"; shift 2 ;;
    --notes) NOTES="${2:?--notes needs a path}"; shift 2 ;;
    --skip-notarization) SKIP_NOTARIZATION=1; shift ;;
    --publish) PUBLISH=1; shift ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown argument: $1 (see --help)" ;;
  esac
done

IDENTITY="${CRA_SIGN_IDENTITY:-Developer ID Application: Lei Zheng (M4HEF73UMB)}"
TEAM_ID="${CRA_TEAM_ID:-M4HEF73UMB}"
ARCHS="${CRA_ARCHS:-arm64}"
SPARKLE_ACCOUNT="${CRA_SPARKLE_ACCOUNT:-From}"
NOTARY_PROFILE="${CRA_NOTARY_PROFILE:-NoType-Notarization}"
R2_BUCKET="${CRA_R2_BUCKET:-from-updates}"
R2_ENV_FILE="${CRA_R2_ENV_FILE:-$HOME/Develop/celia/apps/server/.env.production}"
RETAIN_VERSIONS=2
SPARKLE_BIN=vendor/sparkle/bin

# A dev version (0.0.0-dev) never updates (scripts/build.sh, NewestCopy); a release needs a real one.
[ -n "$VERSION" ] || fail "--version is required, e.g. --version 2.0.0"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || fail "version must be like 2.0.0, not $VERSION"
# Sparkle compares CFBundleVersion: a UTC timestamp keeps every release newer than the last.
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "build number must be numeric: $BUILD_NUMBER"
[ -z "$NOTES" ] || [ -f "$NOTES" ] || fail "release notes not found: $NOTES"
[ "$IDENTITY" != "-" ] || fail "an update must be signed with a Developer ID (CRA_SIGN_IDENTITY)"
grep -qF "\"$IDENTITY\"" <<< "$(security find-identity -v -p codesigning)" || fail "signing identity not in the keychain: $IDENTITY"

if [ "$SKIP_NOTARIZATION" = 0 ]; then
  if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    unset NOTARY_KEYCHAIN_PROFILE
  else
    log "Checking notarytool profile '$NOTARY_PROFILE'"
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null 2>&1 ||
      fail "notarytool keychain profile '$NOTARY_PROFILE' is unavailable. Create it with
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id $TEAM_ID
or pass --skip-notarization (Sparkle installs the update; Gatekeeper is not consulted for it)."
    export NOTARY_KEYCHAIN_PROFILE="$NOTARY_PROFILE"
  fi
fi

# Reads one KEY=value line of the R2 env file without sourcing it; prints nothing else.
env_value() {
  local line
  line="$(grep -E "^(export )?$1=" "$R2_ENV_FILE" | tail -n 1)" || return 1
  line="${line#export }"; line="${line#*=}"
  line="${line%\"}"; line="${line#\"}"; line="${line%\'}"; line="${line#\'}"
  [ -n "$line" ] && printf '%s' "$line"
}
if [ "$PUBLISH" = 1 ]; then
  command -v rclone >/dev/null 2>&1 || fail "rclone is required for --publish (brew install rclone)"
  [ -f "$R2_ENV_FILE" ] || fail "R2 env file not found: $R2_ENV_FILE"
  for key in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY; do
    env_value "$key" >/dev/null || fail "$key missing in $R2_ENV_FILE"
  done
fi

# The installed copies only accept archives signed by the key whose public half is in Info.plist.
PLIST_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' resources/Info.plist)"
if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
  scripts/fetch-sparkle.sh >/dev/null
  KEYCHAIN_KEY="$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null)" ||
    fail "no Sparkle key '$SPARKLE_ACCOUNT' in the login keychain (docs/release.md, Updates)"
  [ "$KEYCHAIN_KEY" = "$PLIST_KEY" ] || fail "keychain Sparkle key '$SPARKLE_ACCOUNT' does not match SUPublicEDKey in resources/Info.plist"
fi

# A release ships the newest stable CEF: Chromium fixes security bugs only in its newest
# version. CRA_ALLOW_OLD_CEF=1 ships the pinned one anyway (an urgent fix while the new CEF
# is still building); say so in the release notes.
if [ "${CRA_ALLOW_OLD_CEF:-}" != 1 ]; then
  scripts/check-cef-update.sh --check ||
    fail "CEF is behind (CRA_ALLOW_OLD_CEF=1 to ship it anyway)"
fi

export CRA_VERSION="$VERSION" CRA_BUILD="$BUILD_NUMBER" CRA_SIGN_IDENTITY="$IDENTITY"
# Release builds carry the update feed (scripts/build.sh drops it otherwise).
export CRA_RELEASE=1

rm -rf build/dist
UPDATE_DIR=build/dist/update
UPDATE_APP=""
for ARCH in $ARCHS; do
  log "Building From $VERSION ($BUILD_NUMBER) for $ARCH"
  CRA_ARCH="$ARCH" scripts/build.sh release
  # build.sh's rule: the host CPU builds build/From.app, the other one build/<arch>/From.app.
  if [ "$ARCH" = "$(uname -m)" ]; then APP="build/From.app"; else APP="build/$ARCH/From.app"; fi
  SUFFIX="$(scripts/asset-suffix.sh "$APP")"

  [ "$(plist "$APP" CFBundleShortVersionString)" = "$VERSION" ] || fail "built version is not $VERSION"
  [ "$(plist "$APP" CFBundleVersion)" = "$BUILD_NUMBER" ] || fail "built CFBundleVersion is not $BUILD_NUMBER"
  codesign --verify --deep --strict "$APP"
  SIGNATURE_INFO="$(codesign -dv "$APP" 2>&1)"
  grep -qx "TeamIdentifier=$TEAM_ID" <<< "$SIGNATURE_INFO" || fail "$APP is not signed by team $TEAM_ID"

  if [ "$SKIP_NOTARIZATION" = 0 ]; then
    # Notarize the app first (as a zip), staple it, then package the stapled app.
    TMPZIP="$(mktemp -d /tmp/from-notarize.XXXXXX)/From.zip"
    ditto -c -k --keepParent "$APP" "$TMPZIP"
    scripts/notarize.sh "$TMPZIP" "$APP"
    rm -rf "$(dirname "$TMPZIP")"
  fi

  scripts/package.sh "$APP"

  if [ "$SKIP_NOTARIZATION" = 0 ]; then
    scripts/notarize.sh "build/dist/From$SUFFIX.dmg"
    # On its own line so set -e fails the release when Gatekeeper rejects the app.
    spctl --assess --type execute --verbose=2 "$APP"
    echo "Gatekeeper accepts $APP"
  else
    echo "Notarization skipped: Sparkle installs this update, but a first install from the DMG needs right-click ▸ Open." >&2
  fi

  if [ "$ARCH" = arm64 ]; then
    UPDATE_APP="$APP"
    mkdir -p "$UPDATE_DIR"
    cp "build/dist/From$SUFFIX.zip" "$UPDATE_DIR/From-$VERSION-$BUILD_NUMBER.zip"
  fi
done
(cd build/dist && shasum -a 256 From*.zip From*.dmg > SHA256SUMS.txt)

[ -n "$UPDATE_APP" ] || { echo "No arm64 build: no update written (the feed is Apple silicon only)." >&2; exit 0; }

ZIP_NAME="From-$VERSION-$BUILD_NUMBER.zip"
ZIP="$UPDATE_DIR/$ZIP_NAME"
FEED_URL="$(plist "$UPDATE_APP" SUFeedURL)"
[[ "$FEED_URL" =~ ^(https://[^/]+)/(.+)/appcast\.xml$ ]] || fail "SUFeedURL must be https://<host>/<prefix>/appcast.xml: $FEED_URL"
R2_PREFIX="${BASH_REMATCH[2]}"
DOWNLOAD_PREFIX="${FEED_URL%/*}/"
[ "$(plist "$UPDATE_APP" SUPublicEDKey)" = "$PLIST_KEY" ] || fail "the app's SUPublicEDKey is not resources/Info.plist's"

log "Writing the appcast"
scripts/appcast.sh "$ZIP" "$UPDATE_APP" "$NOTES"
APPCAST="$UPDATE_DIR/appcast.xml"
xmllint --noout "$APPCAST"
xp() { xmllint --xpath "string(//*[local-name()='item']/$1)" "$APPCAST"; }
[ "$(xp "*[local-name()='version']")" = "$BUILD_NUMBER" ] || fail "appcast version is not $BUILD_NUMBER"
[ "$(xp "*[local-name()='enclosure']/@url")" = "$DOWNLOAD_PREFIX$ZIP_NAME" ] || fail "unexpected appcast URL: $(xp "*[local-name()='enclosure']/@url")"
SIGNATURE="$(xp "*[local-name()='enclosure']/@*[local-name()='edSignature']")"
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/sign_update" --ed-key-file - --verify "$ZIP" "$SIGNATURE"
else
  "$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$ZIP" "$SIGNATURE"
fi
echo "EdDSA signature verifies"

if [ "$PUBLISH" = 1 ]; then
  log "Uploading to r2:$R2_BUCKET/$R2_PREFIX/"
  RCLONE_DIR="$(mktemp -d /tmp/from-rclone.XXXXXX)"
  trap 'rm -rf "$RCLONE_DIR"' EXIT
  (
    umask 077
    {
      printf '[r2]\ntype = s3\nprovider = Cloudflare\nacl = private\n'
      printf 'access_key_id = %s\n' "$(env_value R2_ACCESS_KEY_ID)"
      printf 'secret_access_key = %s\n' "$(env_value R2_SECRET_ACCESS_KEY)"
      printf 'endpoint = https://%s.r2.cloudflarestorage.com\n' "$(env_value R2_ACCOUNT_ID)"
    } > "$RCLONE_DIR/rclone.conf"
  )
  upload() {  # upload <file> <key> <content type> <cache control>
    rclone copyto "$1" "r2:$R2_BUCKET/$R2_PREFIX/$2" --config "$RCLONE_DIR/rclone.conf" \
      --s3-no-check-bucket --retries 5 \
      --header-upload "Content-Type: $3" --header-upload "Cache-Control: $4"
  }
  # Archive first, appcast last: a client must never see an item whose archive is missing.
  upload "$ZIP" "$ZIP_NAME" application/zip "public, max-age=31536000, immutable"
  upload "$APPCAST" appcast.xml application/xml "no-cache, no-store, must-revalidate"
  curl -fsSI "$DOWNLOAD_PREFIX$ZIP_NAME" >/dev/null || fail "the uploaded archive is not publicly reachable"
  PUBLISHED="$(curl -fsSL "$FEED_URL" | xmllint --xpath "string(//*[local-name()='item']/*[local-name()='version'])" -)"
  [ "$PUBLISHED" = "$BUILD_NUMBER" ] || fail "the published feed does not serve build $BUILD_NUMBER"

  # Keep the newest archives only; names end in -<build>.zip, builds are fixed-width timestamps.
  STALE="$(rclone lsf "r2:$R2_BUCKET/$R2_PREFIX/" --config "$RCLONE_DIR/rclone.conf" --include 'From-*.zip' |
    sort -t- -k3 -r | tail -n +$((RETAIN_VERSIONS + 1)))"
  for stale in $STALE; do
    [ "$stale" != "$ZIP_NAME" ] || continue
    log "Removing old archive $stale"
    rclone deletefile "r2:$R2_BUCKET/$R2_PREFIX/$stale" --config "$RCLONE_DIR/rclone.conf"
  done
fi

printf '\nFrom %s (build %s)\n' "$VERSION" "$BUILD_NUMBER"
printf 'App:      %s\n' "$UPDATE_APP"
printf 'Update:   %s\n' "$ZIP"
printf 'Appcast:  %s\n' "$APPCAST"
printf 'DMG:      %s\n' "build/dist/From.dmg"
printf 'Feed:     %s\n' "$FEED_URL"
[ "$SKIP_NOTARIZATION" = 0 ] || printf 'Notarization: skipped\n'
if [ "$PUBLISH" = 0 ]; then
  printf '\nNot published. Re-run with --publish to upload to r2:%s/%s/\n' "$R2_BUCKET" "$R2_PREFIX"
else
  printf 'Published: %s\n' "$DOWNLOAD_PREFIX$ZIP_NAME"
fi
