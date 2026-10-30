#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_TAG="${1:-}"
RELEASE_ARCH="${2:-}"
if [[ $# -ne 2 || ! "$RELEASE_TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo 'Usage: bash Scripts/release.sh vMAJOR.MINOR.PATCH arm64|x86_64' >&2
  exit 2
fi
case "$RELEASE_ARCH" in arm64|x86_64) ;; *) echo 'Architecture must be arm64 or x86_64.' >&2; exit 2 ;; esac
RELEASE_VERSION="${RELEASE_TAG#v}"
RELEASE_BUILD_NUMBER="${RELEASE_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
if [[ ! "$RELEASE_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo 'RELEASE_BUILD_NUMBER must be a positive integer.' >&2
  exit 2
fi

cd "$PROJECT_DIR"
export BUILD_DIR="${BUILD_DIR:-$PROJECT_DIR/build/release-$RELEASE_ARCH}"
export CONFIGURATION=Release
bash Scripts/build.sh -destination 'generic/platform=macOS' \
  "ARCHS=$RELEASE_ARCH" ONLY_ACTIVE_ARCH=NO \
  "MARKETING_VERSION=$RELEASE_VERSION" "CURRENT_PROJECT_VERSION=$RELEASE_BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

RELEASE_APP="$BUILD_DIR/Build/Products/Release/Crab.app"
# Validate the actual products before packaging; never change a signed bundle.
python3 - "$PROJECT_DIR" "$RELEASE_APP" "$RELEASE_ARCH" "$RELEASE_VERSION" "$RELEASE_BUILD_NUMBER" <<'PY'
import pathlib
import plistlib
import subprocess
import sys

root, app, arch, version, build = sys.argv[1:]
root, app = pathlib.Path(root), pathlib.Path(app)
extension = app / "Contents/PlugIns/CrabFinder.appex"
for bundle, identifier, entitlement_file in [
    (app, "dev.crab.Crab", root / "Crab/Crab.entitlements"),
    (extension, "dev.crab.Crab.FinderExtension", root / "FinderExtension/FinderExtension.entitlements"),
]:
    with (bundle / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if (info["CFBundleIdentifier"], info["CFBundleShortVersionString"], info["CFBundleVersion"]) != (identifier, version, build):
        raise SystemExit("Unexpected bundle identity or version: " + bundle.name)
    binary = bundle / "Contents/MacOS" / info["CFBundleExecutable"]
    actual_archs = subprocess.check_output(["xcrun", "lipo", "-archs", str(binary)], text=True).split()
    if actual_archs != [arch]:
        raise SystemExit("Unexpected architectures: " + bundle.name + " " + repr(actual_archs))
    subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)
    signature = subprocess.check_output(["codesign", "--display", "--verbose=2", str(bundle)], stderr=subprocess.STDOUT, text=True)
    if "Signature=adhoc" not in signature.splitlines():
        raise SystemExit("Expected ad-hoc signature: " + bundle.name)
    entitlements = plistlib.loads(subprocess.check_output(
        ["codesign", "--display", "--entitlements", ":-", str(bundle)], stderr=subprocess.DEVNULL))
    with entitlement_file.open("rb") as file:
        expected = plistlib.load(file)
    if any(entitlements.get(key) != value for key, value in expected.items()):
        raise SystemExit("Missing required entitlements: " + bundle.name)
    if entitlements.get("com.apple.security.get-task-allow"):
        raise SystemExit("Release bundle must not allow debugging: " + bundle.name)
webp_archs = subprocess.check_output(["xcrun", "lipo", "-archs", str(root / "Support/WebP/lib/libwebp.a")], text=True).split()
if webp_archs != [arch]:
    raise SystemExit("Unexpected WebP architectures: " + repr(webp_archs))
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print("Verified " + arch + " ad-hoc bundles, entitlements, and version " + version + " (" + build + ").")
PY

RELEASE_OUTPUT="$BUILD_DIR/release"
mkdir -p "$RELEASE_OUTPUT"
RELEASE_STAGE="$(mktemp -d "$BUILD_DIR/.crab-release.XXXXXX")"
trap 'rm -rf "$RELEASE_STAGE"' EXIT
RELEASE_ZIP="Crab-$RELEASE_TAG-macOS-$RELEASE_ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE_APP" "$RELEASE_STAGE/$RELEASE_ZIP"
ditto -x -k "$RELEASE_STAGE/$RELEASE_ZIP" "$RELEASE_STAGE/unpacked"
codesign --verify --deep --strict "$RELEASE_STAGE/unpacked/Crab.app"
(
  cd "$RELEASE_STAGE"
  shasum -a 256 "$RELEASE_ZIP" > "$RELEASE_ZIP.sha256"
)
mv "$RELEASE_STAGE/$RELEASE_ZIP" "$RELEASE_STAGE/$RELEASE_ZIP.sha256" "$RELEASE_OUTPUT/"
printf '\nRelease package: %s/%s\n' "$RELEASE_OUTPUT" "$RELEASE_ZIP"
