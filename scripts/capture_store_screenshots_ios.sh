#!/usr/bin/env bash
# iOS-Simulator counterpart to scripts/capture_store_screenshots.sh. Captures
# the 8 shots from docs/STORE_LISTING.md's shot list for the 6.9" iPhone
# class (iPhone 17 Pro Max simulator), plus the iPad 13" class (iPad Pro
# 13-inch (M5) simulator) with WITH_IPAD=1 (see DEVICES below). Output goes
# to docs/store/screenshots/ios/<slug>/.
#
# Method: there is no adb/uiautomator equivalent on iOS, and driving the
# Simulator via AppleScript/System Events requires Accessibility permissions
# this sandboxed environment doesn't have (see tmp/wrapups/ toolchain_findings
# from the session that first tried it). Instead:
#
#   1. `integration_test/capture_ios_screenshots_test.dart` drives the REAL
#      app on the booted simulator from inside a `flutter test -d <udid>`
#      process, using ordinary WidgetTester finders/taps (find.text,
#      tester.tap, tester.pumpAndSettle) — ordinary widget-test code, just
#      running against the real rendering/gesture pipeline on-device instead
#      of the Dart-VM "flutter tester" target.
#   2. That test can't shell out to `xcrun simctl` itself (an iOS app sandbox
#      can't spawn arbitrary host processes), so after each screen settles it
#      prints a "SHOT_READY:<name>" marker. `flutter test -d <udid>` forwards
#      print() from the on-device test straight to this script's stdin, so
#      this script tails it and fires `xcrun simctl io <udid> screenshot`
#      the instant each marker appears.
#
# Usage: scripts/capture_store_screenshots_ios.sh
#        ONLY=6.9in scripts/capture_store_screenshots_ios.sh   # one device
#        SIM_PREFIX=Shots scripts/capture_store_screenshots_ios.sh
#          # own simulators ("Shots iPhone 17 Pro Max", ...), created on demand
#
# Requires: Xcode + iOS Simulator (confirmed present: Xcode 26.3) and the
# repo's Flutter on PATH (~/flutter-stable/bin, prepended below). macOS has no
# `timeout`, so nothing here uses it; a hung run is the test's own job to fail
# (its finders give up with a DIAGNOSTIC line).
#
# Data: the test runs lib/main_screenshots.dart on MOCK services and seeds only
# those in-memory mocks, with --dart-define=E2E=true (E2eMode) on top. It
# never touches Firebase / production.
#
# NEVER run this while another `flutter` build/run is in progress elsewhere
# in the repo (repo convention: no parallel flutter builds). Never run the
# Android and iOS capture scripts at the same time for the same reason.

set -uo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
export PATH="$HOME/flutter-stable/bin:$PATH"

TEST_FILE="integration_test/capture_ios_screenshots_test.dart"
OUT_ROOT="$REPO_ROOT/docs/store/screenshots/ios"
BUNDLE_ID="com.sagearbor.taskcaster.app"

# device-type-id : output-slug : friendly name, one per line.
DEVICES=(
  "iPhone 17 Pro Max:6.9in:6.9-inch (iPhone 17 Pro Max)"
)
# The app is iPhone-only (TARGETED_DEVICE_FAMILY = 1 since the first
# TestFlight build), so App Store Connect asks for no iPad shots, and on an
# iPad simulator it only runs letterboxed in iPhone compatibility mode.
# WITH_IPAD=1 captures the iPad set anyway; useful once the target adds "2".
if [ -n "${WITH_IPAD:-}" ]; then
  DEVICES+=("iPad Pro 13-inch (M5):ipad-13in:iPad 13-inch (M5)")
fi

# Finds (or creates) a simulator of the given device-type name, boots it, and
# echoes its UDID.
boot_device() {
  local device_type="$1"
  local udid
  # SIM_PREFIX picks a dedicated simulator by name (e.g. "Shots" matches
  # "Shots iPhone 17 Pro Max"), so a capture never shares a simulator that
  # another run is using. Created on first use.
  local sim_name="${SIM_PREFIX:+$SIM_PREFIX }$device_type"
  udid="$(xcrun simctl list devices available 2>/dev/null \
    | grep -E "^ +${sim_name//[()]/.} \(" | grep -oE '[0-9A-F-]{36}' | head -1)"
  if [ -z "$udid" ]; then
    echo "No existing '$device_type' simulator found; creating one..." >&2
    local runtime
    runtime="$(xcrun simctl list runtimes 2>/dev/null | grep -i iOS | tail -1 \
      | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.[^ ]+')"
    udid="$(xcrun simctl create "$sim_name" "$device_type" "$runtime")"
  fi
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
  case "$device_type" in
    iPad*)
      # iPadOS 26 defaults new simulators to "Windowed Apps": the app opens
      # in a small floating window over the wallpaper. Switch to "Full
      # Screen Apps" (Settings > Multitasking & Gestures) and reboot.
      xcrun simctl spawn "$udid" defaults write com.apple.springboard \
        SBMedusaMultitaskingEnabled -bool NO >/dev/null 2>&1
      xcrun simctl spawn "$udid" defaults write com.apple.springboard \
        SBChamoisWindowingEnabled -bool NO >/dev/null 2>&1
      xcrun simctl shutdown "$udid" >/dev/null 2>&1
      xcrun simctl boot "$udid" >/dev/null 2>&1
      xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
      ;;
  esac
  echo "$udid"
}

# Runs the integration test against $1 (udid), watching its stdout for
# SHOT_READY:<name> markers and screenshotting into $2 (output dir) the
# instant each one appears. Blocks until the flutter test process exits.
run_and_capture() {
  local udid="$1" out_dir="$2"
  mkdir -p "$out_dir"
  # Old shot names must not linger next to the new set.
  rm -f "$out_dir"/*.png
  local log="$REPO_ROOT/tmp/ios_screenshots_$$.log"

  # Fresh install every run so onboarding (shot 1) always shows — a
  # left-over install from a prior debug run persists shared_preferences'
  # "has seen onboarding" flag and skips straight to the login screen.
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true

  echo "Running $TEST_FILE on $udid (log: $log)..."
  # E2E=true turns E2eMode on (no Arena grade writes, posts not shareable)
  # on top of the mock services: belt and braces, nothing reaches production.
  flutter test "$TEST_FILE" -d "$udid" --dart-define=E2E=true >"$log" 2>&1 &
  local test_pid=$!

  # Tail the log as it grows, screenshotting on every SHOT_READY marker,
  # until the flutter test process exits.
  local last_line=0
  while kill -0 "$test_pid" 2>/dev/null; do
    sleep 0.2
    local total_lines
    total_lines="$(wc -l <"$log" 2>/dev/null || echo 0)"
    if [ "$total_lines" -gt "$last_line" ]; then
      sed -n "$((last_line + 1)),${total_lines}p" "$log" \
        | grep -oE 'SHOT_READY:[A-Za-z0-9_]+' | while read -r marker; do
        local name="${marker#SHOT_READY:}"
        case "$name" in
          _*) continue ;; # internal (non-shot) settle markers start with _
        esac
        echo "  capturing $name"
        xcrun simctl io "$udid" screenshot "$out_dir/$name.png" >/dev/null 2>&1
      done
      last_line="$total_lines"
    fi
  done
  wait "$test_pid"
  local exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    echo "WARNING: flutter test exited with code $exit_code — see $log" >&2
    tail -60 "$log" >&2
  fi
  echo "Full test log kept at $log"
  return "$exit_code"
}

overall_status=0
for entry in "${DEVICES[@]}"; do
  IFS=':' read -r device_type slug friendly <<<"$entry"
  if [ -n "${ONLY:-}" ] && [ "$ONLY" != "$slug" ]; then continue; fi
  echo "== $friendly =="
  udid="$(boot_device "$device_type")"
  echo "Booted $udid"
  # Apple's marketing status bar: 9:41, full signal, full battery.
  xcrun simctl status_bar "$udid" override --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true
  out_dir="$OUT_ROOT/$slug"
  if ! run_and_capture "$udid" "$out_dir"; then
    overall_status=1
  fi
  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
  echo "Shutting down $udid"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  echo "-- $friendly done. Screenshots in $out_dir --"
  ls -la "$out_dir" 2>/dev/null
done

exit "$overall_status"
