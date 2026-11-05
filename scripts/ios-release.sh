#!/usr/bin/env bash
# iOS App Store build: archive (non-interactive, API-key signing) then export.
# flutter build ipa can't forward the -authenticationKey* flags, so archive and
# export go through xcodebuild directly (see docs/IOS_RELEASE.md).
# The export step may show ONE macOS dialog asking to let codesign use the
# "iPhone Distribution: Sage Arbor" key — click "Always Allow".
set -euo pipefail
cd "$(dirname "$0")/.."
source ~/.config/asc/asc.env
FLUTTER=${FLUTTER:-flutter}
STEP=${1:-all}   # archive | export | upload | all
ARCHIVE=build/ios/archive/Runner.xcarchive
AUTH=(-allowProvisioningUpdates
  -authenticationKeyPath "$EXPO_ASC_API_KEY_PATH"
  -authenticationKeyID "$EXPO_ASC_KEY_ID"
  -authenticationKeyIssuerID "$EXPO_ASC_ISSUER_ID")

if [[ $STEP == archive || $STEP == all ]]; then
  "$FLUTTER" build ios --release --config-only
  (cd ios && pod install)
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
    -configuration Release -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" archive "${AUTH[@]}"
fi
if [[ $STEP == export || $STEP == all ]]; then
  xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist ios/ExportOptions.plist -exportPath build/ios/ipa "${AUTH[@]}"
fi
if [[ $STEP == upload || $STEP == all ]]; then
  xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios \
    --apiKey "$EXPO_ASC_KEY_ID" --apiIssuer "$EXPO_ASC_ISSUER_ID"
fi
