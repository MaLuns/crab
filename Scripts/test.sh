#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$PROJECT_DIR/build}"
source "$PROJECT_DIR/Scripts/temporary-products.sh"
crab_prepare_temporary_products
xcodebuild -project "$PROJECT_DIR/Crab.xcodeproj" -scheme Crab \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" test "$@" \
  "CONFIGURATION_BUILD_DIR=$CRAB_PRODUCTS_STAGE/products"
