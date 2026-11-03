#!/usr/bin/env bash
# Builds build/Hark.app (and with --dist, a zip + SHA-256 for release).
#
# Signing: ad-hoc by default. Set CODESIGN_IDENTITY to a "Developer ID Application"
# identity to sign for distribution, and NOTARY_PROFILE to a notarytool keychain
# profile to notarize and staple.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(tr -d '[:space:]' < VERSION)
APP=build/Hark.app
IDENTITY=${CODESIGN_IDENTITY:--}

scripts/fetch-deps.sh

# SWIFT_BUILD_FLAGS lets packagers add flags, e.g. --disable-sandbox inside Homebrew's sandbox.
read -r -a EXTRA_FLAGS <<< "${SWIFT_BUILD_FLAGS:-}"
swift build -c release --arch arm64 ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}
BIN_DIR=$(swift build -c release --arch arm64 ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Hark" "$APP/Contents/MacOS/Hark"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns vendor/whistle/whistle.cact LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"

SIGN_ARGS=(--force --options runtime --entitlements Resources/Hark.entitlements --sign "$IDENTITY")
[[ $IDENTITY != "-" ]] && SIGN_ARGS+=(--timestamp)
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, signed with ${IDENTITY/-/ad-hoc identity})"

if [[ ${1:-} == --dist ]]; then
  ZIP=build/Hark-$VERSION.zip
  rm -f "$ZIP"
  if [[ -n ${NOTARY_PROFILE:-} ]]; then
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
  fi
  ditto -c -k --keepParent "$APP" "$ZIP"
  (cd build && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
  echo "Packaged $ZIP"
  cat "$ZIP.sha256"
fi
