#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v xcodegen >/dev/null; then
 echo "XcodeGen mangler. Installér på Mac med: brew install xcodegen" >&2
 exit 2
fi
xcodegen generate
xcodebuild -project Scan3DLiDAR.xcodeproj -scheme Scan3DLiDAR -configuration Debug \
 -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
