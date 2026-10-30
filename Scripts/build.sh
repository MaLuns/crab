#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$PROJECT_DIR/build}"
CONFIGURATION="${CONFIGURATION:-Release}"
xcodebuild -project "$PROJECT_DIR/Crab.xcodeproj" -scheme Crab \
  -configuration "$CONFIGURATION" -derivedDataPath "$BUILD_DIR" build "$@"
printf '\n构建完成：%s\n' "$BUILD_DIR/Build/Products/$CONFIGURATION/Crab.app"
