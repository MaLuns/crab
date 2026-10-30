#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$PROJECT_DIR/build}"
xcodebuild -project "$PROJECT_DIR/Crab.xcodeproj" -scheme Crab \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" test "$@"
