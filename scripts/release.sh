#!/bin/bash
# Full distributable build: build, sign, notarize, package and notarize the DMG,
# once per CPU.
#   CRA_VERSION=0.1.0 CRA_SIGN_IDENTITY="Developer ID Application: …" scripts/release.sh
# Every release ships Apple silicon (From.dmg, From.zip) and Intel
# (From-Intel.dmg, From-Intel.zip). CRA_ARCHS="arm64" (or "x86_64")
# builds one; the Release workflow runs one per job and merges them.
# Without CRA_SIGN_IDENTITY it still produces an ad-hoc build and packages, so
# the pipeline can be exercised before certificates exist.
set -euo pipefail
cd "$(dirname "$0")/.."
export CRA_VERSION="${CRA_VERSION:-0.1.0}"
# One build number for both CPUs.
export CRA_BUILD="${CRA_BUILD:-$(date +%Y%m%d%H%M)}"
IDENTITY="${CRA_SIGN_IDENTITY:--}"
ARCHS="${CRA_ARCHS:-arm64 x86_64}"

# A release ships the newest stable CEF: Chromium fixes security bugs only in its newest
# version. CRA_ALLOW_OLD_CEF=1 ships the pinned one anyway (an urgent fix while the new CEF
# is still building); say so in the release notes.
if [ "${CRA_ALLOW_OLD_CEF:-}" != 1 ]; then
  scripts/check-cef-update.sh --check ||
    { echo "Release stopped: CEF is behind (CRA_ALLOW_OLD_CEF=1 to ship it anyway)" >&2; exit 1; }
fi

rm -rf build/dist
for ARCH in $ARCHS; do
  CRA_ARCH="$ARCH" scripts/build.sh release
  # build.sh's rule: the host CPU builds build/From.app, the other one build/<arch>/From.app.
  if [ "$ARCH" = "$(uname -m)" ]; then APP="build/From.app"; else APP="build/$ARCH/From.app"; fi
  SUFFIX="$(scripts/asset-suffix.sh "$APP")"

  if [ "$IDENTITY" != "-" ]; then
    # Notarize the app first (as a zip), staple it, then package the stapled app.
    TMPZIP="$(mktemp -d /tmp/cra-notarize.XXXXXX)/Cra.zip"
    ditto -c -k --keepParent "$APP" "$TMPZIP"
    scripts/notarize.sh "$TMPZIP" "$APP"
    rm -rf "$(dirname "$TMPZIP")"
  fi

  scripts/package.sh "$APP"

  if [ "$IDENTITY" != "-" ]; then
    scripts/notarize.sh "build/dist/From$SUFFIX.dmg"
    # Re-zip the stapled app so the zip download carries the ticket too.
    ditto -c -k --keepParent "$APP" "build/dist/From$SUFFIX.zip"
    # On its own line so set -e fails the release when Gatekeeper rejects the app.
    spctl --assess --type execute --verbose=2 "$APP"
    echo "Gatekeeper accepts $APP"
  else
    echo "Ad-hoc build: not notarized. Set CRA_SIGN_IDENTITY and notary credentials for a distributable build." >&2
  fi
done
(cd build/dist && shasum -a 256 From*.zip From*.dmg > SHA256SUMS.txt)
echo "Release artifacts in build/dist:"
ls -la build/dist
