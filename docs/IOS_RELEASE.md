# iOS release (TestFlight / App Store)

- App Store Connect app: **TaskCaster Party**, Apple ID `6824157028`, bundle `com.sagearbor.taskcaster.app`, SKU `taskcaster-app`, team `553Y9KWR84`.
- Bundle id capabilities: Push Notifications, Sign in with Apple (both registered 2026-10-18).
- iPhone only (`TARGETED_DEVICE_FAMILY = 1`), so App Store Connect does not ask for iPad screenshots.

## Build and upload

```bash
# unlock the shared signing keychain first (see ship-mobile-app skill, reference/ios.md)
FLUTTER=~/flutter/bin/flutter scripts/ios-release.sh all   # archive -> export -> TestFlight upload
```

The script signs with the machine-level App Store Connect API key (`~/.config/asc/asc.env`), so no Xcode login is needed. Bump `version:` in `pubspec.yaml` before each upload; Android and iOS ship the same version.

Apple warns that the iOS 13.0 deployment target must be raised to 15.0 before April 2027.
