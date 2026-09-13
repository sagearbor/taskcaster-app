#!/usr/bin/env bash
# Runs the Firestore + Storage security rules tests against the Firebase
# emulators (Firestore + Storage only — no need to spin up Auth/Hosting).
#
# Usage: test/rules/run.sh   (run from anywhere; it cd's to the repo root)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# firebase-tools' emulators require a JDK >= 21. If the default `java` on
# PATH is older (e.g. a homebrew openjdk@17 shimmed first), prefer a known
# openjdk@21 install when one exists rather than fail outright.
if command -v java >/dev/null 2>&1; then
  JAVA_MAJOR="$(java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')"
else
  JAVA_MAJOR=0
fi
if [ "${JAVA_MAJOR:-0}" -lt 21 ] 2>/dev/null; then
  for candidate in /opt/homebrew/opt/openjdk@21/bin /usr/local/opt/openjdk@21/bin; do
    if [ -x "$candidate/java" ]; then
      export PATH="$candidate:$PATH"
      break
    fi
  done
fi

cd "$SCRIPT_DIR"
npm ci || npm install

cd "$REPO_ROOT"
firebase emulators:exec --only firestore,storage --project taskmaster-app-3d480 \
  "cd test/rules && npm test"
