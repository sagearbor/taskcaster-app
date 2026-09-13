#!/usr/bin/env bash
# Render the six HOUSE video clips. Thin wrapper around make_house_clips.js so
# the job can be run without remembering the node invocation.
#
#   ./scripts/house_clips/make_house_clips.sh [--source FILE] [--out DIR]
#
# Requires `npm install` to have been run in functions/ (the ffmpeg-static
# binary lives there). Outputs starter-XX.mp4, ready to upload to
# house/<taskId>.mp4 in the bucket.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "${HERE}/make_house_clips.js" "$@"
