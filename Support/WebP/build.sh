#!/bin/bash
set -euo pipefail
CRAB_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CRAB_SOURCE="$CRAB_ROOT/Vendor/libwebp"
CRAB_BUILD="$CRAB_ROOT/build/vendor-webp"
CRAB_ARCHS="${ARCHS:-arm64 x86_64}"
CRAB_CLANG="$(xcrun --find clang)"
CRAB_SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$CRAB_BUILD" "$CRAB_ROOT/Support/WebP/lib"
CRAB_SCRIPT_SHA="$(shasum -a 256 "$0" | awk '{print $1}')"
CRAB_LIBS=()
for CRAB_ARCH in $CRAB_ARCHS; do
  case "$CRAB_ARCH" in arm64|x86_64) ;; *) echo "Unsupported WebP architecture: $CRAB_ARCH" >&2; exit 1;; esac
  CRAB_DIR="$CRAB_BUILD/$CRAB_ARCH"
  mkdir -p "$CRAB_DIR"
  CRAB_CONFIG="$CRAB_SCRIPT_SHA|$CRAB_ARCH|$CRAB_SDK"
  if [ ! -f "$CRAB_DIR/Makefile" ] || [ ! -f "$CRAB_DIR/config.id" ] || [ "$(cat "$CRAB_DIR/config.id")" != "$CRAB_CONFIG" ] || [ "$CRAB_SOURCE/configure" -nt "$CRAB_DIR/Makefile" ]; then
    (
      cd "$CRAB_DIR"
      CC="$CRAB_CLANG" CFLAGS="-O2 -arch $CRAB_ARCH -isysroot $CRAB_SDK -mmacosx-version-min=13.0" \
        LDFLAGS="-arch $CRAB_ARCH -isysroot $CRAB_SDK -mmacosx-version-min=13.0" \
        "$CRAB_SOURCE/configure" --host="$CRAB_ARCH-apple-darwin" --enable-static --disable-shared \
        --disable-libwebpmux --disable-libwebpdemux --disable-sdl --disable-gl \
        --disable-png --disable-jpeg --disable-tiff --disable-gif --disable-wic > configure.log 2>&1
      printf '%s\n' "$CRAB_CONFIG" > config.id
    )
  fi
  (
    cd "$CRAB_DIR"
    make -j"${CRAB_WEBP_JOBS:-4}" -C sharpyuv > make-sharpyuv.log 2>&1
    make -j"${CRAB_WEBP_JOBS:-4}" -C src > make-webp.log 2>&1
    xcrun libtool -static -o libwebp.a src/.libs/libwebp.a sharpyuv/.libs/libsharpyuv.a
  )
  CRAB_LIBS+=("$CRAB_DIR/libwebp.a")
done
xcrun lipo -create "${CRAB_LIBS[@]}" -output "$CRAB_ROOT/Support/WebP/lib/libwebp.a.tmp"
mv "$CRAB_ROOT/Support/WebP/lib/libwebp.a.tmp" "$CRAB_ROOT/Support/WebP/lib/libwebp.a"
xcrun lipo -info "$CRAB_ROOT/Support/WebP/lib/libwebp.a"
