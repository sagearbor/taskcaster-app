#!/usr/bin/env bash
# iOS App Store build: archive (non-interactive, API-key signing) then export.
# flutter build ipa can't forward the -authenticationKey* flags, so archive and
# export go through xcodebuild directly (see docs/IOS_RELEASE.md).
# The export step may show ONE macOS dialog asking to let codesign use the
# "iPhone Distribution: Sage Arbor" key — click "Always Allow".
set -euo pipefail
export PATH="$HOME/flutter-stable/bin:/opt/homebrew/bin:$PATH"  # flutter/pod/firebase even in a bare shell
cd "$(dirname "$0")/.."
source ~/.config/asc/asc.env
FLUTTER=${FLUTTER:-flutter}
STEP=${1:-all}   # archive | export | upload | all
ARCHIVE=build/ios/archive/Runner.xcarchive
AUTH=(-allowProvisioningUpdates
  -authenticationKeyPath "$EXPO_ASC_API_KEY_PATH"
  -authenticationKeyID "$EXPO_ASC_KEY_ID"
  -authenticationKeyIssuerID "$EXPO_ASC_ISSUER_ID")

# Public build-time keys (e.g. REVENUECAT_IOS_KEY) live outside the repo.
DEFINES=~/.config/taskcaster/dart-defines.env
DEFINE_ARGS=()
[[ -f $DEFINES ]] && DEFINE_ARGS=(--dart-define-from-file="$DEFINES")

if [[ $STEP == archive || $STEP == all ]]; then
  "$FLUTTER" build ios --release --config-only "${DEFINE_ARGS[@]}"
  (cd ios && pod install)
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
    -configuration Release -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" archive "${AUTH[@]}"
fi
unlock_signing_keychain() {
  # The distribution cert lives in a separate keychain that macOS locks at
  # every login/reboot. Its password is stored once in the login keychain
  # (service "fitrival-signing-keychain"), so unlock it here without a prompt.
  local kc=~/.config/fitrival/fitrival-signing.keychain-db pw
  [[ -f $kc ]] || return 0
  if pw=$(security find-generic-password -s fitrival-signing-keychain -w 2>/dev/null); then
    security unlock-keychain -p "$pw" "$kc"
  else
    echo "Signing keychain may be locked; run: security unlock-keychain $kc" >&2
  fi
}

if [[ $STEP == export || $STEP == all ]]; then
  unlock_signing_keychain
  xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist ios/ExportOptions.plist -exportPath build/ios/ipa "${AUTH[@]}"
fi
if [[ $STEP == upload || $STEP == all ]]; then
  xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios \
    --apiKey "$EXPO_ASC_KEY_ID" --apiIssuer "$EXPO_ASC_ISSUER_ID"
fi
