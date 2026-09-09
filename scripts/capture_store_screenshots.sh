#!/usr/bin/env bash
# Captures the 8 Play/App Store screenshots listed in docs/STORE_LISTING.md's
# "Screenshot shot list" section (light theme, per that section's own wording)
# on an Android emulator, into docs/store/screenshots/.
#
# Method: builds the app from lib/main_screenshots.dart (a small dev-only
# entry point added alongside the existing lib/main_mock.dart -- same mock
# services, no Firebase/network required, but with the debug FPS overlay
# hard-disabled so it never pollutes a screenshot), in --profile mode (so
# Flutter's debug-only RenderFlex "overflowed" warning banners are compiled
# out too -- --debug mode showed a real such banner on the Play sheet at this
# screen size; harmless in a real (release) build, but ugly in a screenshot).
# Installs it fresh on the target device, then drives the REAL production
# screens with `adb shell input` taps/text and captures each with
# `adb exec-out screencap -p`. Nothing here is a synthetic test harness --
# every screen is the real widget tree, backed by the app's own seeded mock
# games (game_1 "Saturday Night Shenanigans", 3-player lobby, code PARTY1)
# and the real Quick Play / Drawing Telephone "Practice solo" flows for the
# shots that need a fresh playthrough (task submit -> judge -> scoreboard
# reveal; drawing canvas).
#
# Coordinates are looked up live via `uiautomator dump` + a content-desc/text
# match (see tap_by_desc/tap_by_text below) rather than hardcoded pixels --
# hardcoded taps drifted badly between runs (list order/length on the Home
# screen changes as mock games accumulate a createdAt-sorted history), while
# a text/content-desc match is stable across runs and screen sizes.
#
# Usage: scripts/capture_store_screenshots.sh [device-id]
#   device-id defaults to the first attached adb device (the pixel10_api35
#   emulator, if that's the only one running).
#
# Requires: Flutter 3.22.2 on PATH (tmp/flutter-3.22.2/bin), JDK 17 selected
# (flutter config --jdk-dir, already set at the user level), an Android
# emulator running.
#
# NEVER run this while another `flutter` build/run is in progress elsewhere
# in the repo (repo convention: no parallel flutter builds).

set -euo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
export PATH="$REPO_ROOT/tmp/flutter-3.22.2/bin:$PATH"

DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  DEVICE="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
fi
if [ -z "$DEVICE" ]; then
  echo "No adb device found. Start an Android emulator first." >&2
  exit 1
fi
echo "Using device: $DEVICE"

PKG="com.sagearbor.taskcaster.app"
ACT="$PKG/.MainActivity"
OUT_DIR="$REPO_ROOT/docs/store/screenshots"
DUMP="/tmp/tc_screenshot_dump.xml"
mkdir -p "$OUT_DIR"

adbs() { adb -s "$DEVICE" "$@"; }

# Flutter's semantics tree culls nodes scrolled out of the viewport, so
# uiautomator can't find (and tap_by_desc can't tap) an off-screen widget --
# the Home screen's list is taller than one screen. These bracket a
# find/tap with an explicit scroll to the end that matters.
scroll_home_to_bottom() { adbs shell input swipe 540 1800 540 300 400; sleep 1; }
scroll_home_to_top() { adbs shell input swipe 540 500 540 1900 400; sleep 1; }

# Presses back repeatedly (each press's dismissal/pop animation gets time to
# finish before the next) until the Home screen's distinctive "Invites from
# friends" section header is found, or gives up after $1 tries. Empirically,
# a fixed count of instantaneous KEYCODE_BACK presses is unreliable -- a back
# sent while the previous pop's transition is still animating gets dropped.
go_to_home() {
  local tries="${1:-6}" i
  for ((i = 0; i < tries; i++)); do
    adbs shell uiautomator dump /sdcard/tc_dump.xml >/dev/null
    adbs pull /sdcard/tc_dump.xml "$DUMP" >/dev/null 2>&1
    if find_center "Invites from friends" >/dev/null 2>&1; then
      return 0
    fi
    adbs shell input keyevent KEYCODE_BACK
    sleep 1.5
  done
  echo "go_to_home: did not reach Home after $tries back-presses" >&2
  return 1
}

shot() { # shot <filename-without-ext> [settle-seconds]
  sleep "${2:-1.2}"
  adbs exec-out screencap -p > "$OUT_DIR/$1.png"
  echo "captured $1"
}

# Parses a uiautomator XML dump with Python's stdlib parser (far more
# reliable than grepping XML with regex -- an earlier grep-based version hit
# both false negatives on `set -e` and this environment's `grep` (ugrep)
# erroring out on unbounded `[^>]*` patterns) and prints "x y" for the CENTER
# of the first node whose content-desc or text CONTAINS $1 (a card's whole
# multi-line label is often one content-desc, e.g. "S\nSaturday Night
# Shenanigans\nLobby\n...", so substring match beats a prefix match), or the
# first EditText node if $1 is the literal string EDITTEXT. Exits 1 with
# nothing on stdout if no match, so callers can detect failure via an empty
# $() capture.
find_center() {
  python3 - "$DUMP" "$1" <<'PYEOF'
import sys, xml.etree.ElementTree as ET
dump_path, needle = sys.argv[1], sys.argv[2]
tree = ET.parse(dump_path)

def bounds_of(node):
    b = node.attrib.get('bounds', '')
    nums = [int(n) for n in b.replace('[', ',').replace(']', ',').split(',') if n.lstrip('-').isdigit()]
    if len(nums) != 4:
        return None
    x1, y1, x2, y2 = nums
    return (x1 + x2) // 2, (y1 + y2) // 2

if needle == 'EDITTEXT':
    for node in tree.iter():
        if node.attrib.get('class', '') == 'android.widget.EditText':
            c = bounds_of(node)
            if c:
                print(*c); sys.exit(0)
    sys.exit(1)

# Two passes: EXACT content-desc/text match first (e.g. a dialog's "Finish"
# button vs. its own "Finish Judging?" title, which would otherwise win a
# substring search by appearing first in tree order), falling back to
# substring containment (needed for a card's whole multi-line content-desc,
# e.g. "S\nSaturday Night Shenanigans\nLobby\n...").
for exact in (True, False):
    for node in tree.iter():
        desc = node.attrib.get('content-desc', '')
        text = node.attrib.get('text', '')
        match = (desc == needle or text == needle) if exact else (needle in desc or needle in text)
        if match:
            c = bounds_of(node)
            if c:
                print(*c); sys.exit(0)
sys.exit(1)
PYEOF
}

# Dumps the current UI tree and taps the CENTER of the first element whose
# content-desc starts with $1 (a literal prefix match). Exits non-zero (with
# a clear message) if not found, so a broken selector fails loudly instead of
# tapping the wrong thing.
tap_by_desc() {
  local needle="$1" wait_after="${2:-1.3}"
  adbs shell uiautomator dump /sdcard/tc_dump.xml >/dev/null
  adbs pull /sdcard/tc_dump.xml "$DUMP" >/dev/null 2>&1
  local coords
  if ! coords="$(find_center "$needle")"; then
    echo "tap_by_desc: could not find element matching '$needle'" >&2
    return 1
  fi
  adbs shell input tap $coords
  sleep "$wait_after"
}

type_text_into() { # type_text_into <unused> <text>
  # The video-link / prompt fields in this app have no content-desc, so we
  # locate the (only) focused-after-tap EditText by class instead: tap the
  # first android.widget.EditText found, then type.
  adbs shell uiautomator dump /sdcard/tc_dump.xml >/dev/null
  adbs pull /sdcard/tc_dump.xml "$DUMP" >/dev/null 2>&1
  local coords
  if ! coords="$(find_center EDITTEXT)"; then
    echo "type_text_into: no EditText found on screen" >&2
    return 1
  fi
  adbs shell input tap $coords
  sleep 0.8
  adbs shell input text "$2"
  sleep 0.5
  adbs shell input keyevent 111  # KEYCODE_ESCAPE: dismiss soft keyboard without popping the route
  sleep 0.5
}

echo "== Building profile APK from lib/main_screenshots.dart (no overflow/FPS debug chrome) =="
flutter build apk --profile -t lib/main_screenshots.dart

echo "== Installing fresh (clears prior state so onboarding shows) =="
adbs uninstall "$PKG" >/dev/null 2>&1 || true
adbs install -r build/app/outputs/flutter-apk/app-profile.apk

echo "== Launching =="
adbs shell am start -n "$ACT"
sleep 5

# 1. Onboarding — "Party games for everyone" (first/only page, fresh install)
shot "01_onboarding" 2

tap_by_desc "Let's play" 2
tap_by_desc "Play" 2.5   # anonymous guest sign-in on the login screen

# 2. Home — invites section + jump-back-in games list
shot "02_home" 1.5

# 3. Play sheet — tap the big red "Play" FilledButton (bottom of Home, below
#    the fold -- scroll down first or uiautomator won't see it).
scroll_home_to_bottom
tap_by_desc "Play" 1.3
shot "03_play_sheet" 1

# 4. Game lobby — dismiss the sheet, open the seeded lobby game directly.
# The sheet's dismissal doesn't change Home's scroll offset (still scrolled
# down from the Play tap above), so scroll back to the top first.
adbs shell input keyevent KEYCODE_BACK
sleep 1
scroll_home_to_top
tap_by_desc "Saturday Night Shenanigans" 1.8
shot "04_game_lobby" 1
adbs shell input keyevent KEYCODE_BACK
sleep 1.5

# 5+6+7: Quick Play -> submit the first task -> judge it -> scoreboard reveal.
scroll_home_to_bottom
tap_by_desc "Play" 1.3            # reopen Play sheet
tap_by_desc "Quick Play" 2.5      # solo in-progress game, 5 random tasks

# Open the first task (list item content-desc starts with its title text,
# which is random per run -- tap by class/position instead via the "New task
# available!" banner's View action, which is stable).
tap_by_desc "View" 1.8

# 5. Task view — a prebuilt task with the submit box.
shot "05_task_view" 1

type_text_into "" "https://youtube.com/watch?v=demo123"
tap_by_desc "Submit Video" 2

# Judging: the "Ready to judge!" banner appears once the sole (self) player's
# submission is in.
tap_by_desc "Judge" 1.8
tap_by_desc "Judge All Submissions" 1.8

# 6. Judging screen — scoring a submission (0-10 verdict scale visible).
shot "06_judging" 1

tap_by_desc "Score 8 points" 1.5
tap_by_desc "Reveal the scores" 1.5
tap_by_desc "Finish" 3

# 7. Scoreboard — animated reveal (confetti + WINNER badge), shown
#    immediately after Finish.
shot "07_scoreboard" 0.5

# Close the results screen (X, top-right of the "Task N Results" app bar --
# has no content-desc, so tapped directly), then pop back to Home.
adbs shell input tap 838 112
sleep 1.8
go_to_home

# 8. Drawing Telephone canvas — Play sheet -> Drawing Telephone -> Options ->
#    Practice solo (fully offline, deterministic, no networking).
scroll_home_to_bottom
tap_by_desc "Play" 1.3
tap_by_desc "Drawing Telephone" 1.5
tap_by_desc "Options" 1
# "Practice solo" is below the fold once Options expands.
adbs shell input swipe 540 1800 540 900 400
sleep 1
tap_by_desc "Practice solo" 2.5

# Round 1 asks for a prompt; fill it and submit to reach round 2 (drawing).
type_text_into "" "A dinosaur riding a skateboard"
tap_by_desc "Submit prompt" 2.5

# Sketch a few strokes so the canvas isn't blank in the screenshot.
adbs shell input swipe 300 700 500 700 200
adbs shell input swipe 500 700 500 900 200
adbs shell input swipe 500 900 300 900 200
adbs shell input swipe 300 900 300 700 200
sleep 0.5

shot "08_drawing_telephone_canvas" 0.5

echo "Done. Screenshots in $OUT_DIR"
ls -la "$OUT_DIR"
