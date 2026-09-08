#!/usr/bin/env bash
# Build a signed Android App Bundle for Google Play.
# Requires android/key.properties + the upload keystore (see docs/PLAY_RELEASE.md).
set -euo pipefail
cd "$(dirname "$0")/.."

# Flutter ignores JAVA_HOME when Android Studio ships its own JDK, and Android
# Studio 2026.x bundles JDK 25, which the project's Gradle cannot run on.
# The supported way to pin a JDK is `flutter config --jdk-dir=...`.
if ! flutter config --list 2>/dev/null | grep -q 'jdk-dir'; then
  echo "No JDK pinned for Flutter. Run once (JDK 17 recommended):" >&2
  echo "  flutter config --jdk-dir=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" >&2
  exit 1
fi

flutter build appbundle --release
echo ""
echo "AAB ready: build/app/outputs/bundle/release/app-release.aab"
