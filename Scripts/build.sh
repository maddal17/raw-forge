#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
MODULES_DIR="$BUILD_DIR/modules"
BIN_DIR="$BUILD_DIR/bin"
DIST_APP="$ROOT_DIR/dist/RawForge.app"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"

SWIFTC="$(xcrun --find swiftc)"
SDK_PATH="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
COMMON_FLAGS=(-O -whole-module-optimization -swift-version 6 -target "${ARCH}-apple-macosx14.0" -sdk "$SDK_PATH")

mkdir -p "$MODULES_DIR" "$BIN_DIR" "$ROOT_DIR/dist"

if [ ! -f "$ICON_FILE" ]; then
    echo "[0/5] Generating AppIcon.icns..."
    swift "$ROOT_DIR/Scripts/generate_icon.swift" "$ICON_FILE"
fi

echo "[1/5] Building RawForgeCore static library & module..."
"$SWIFTC" "${COMMON_FLAGS[@]}" \
    -emit-library -static \
    -emit-module \
    -module-name RawForgeCore \
    -emit-module-path "$MODULES_DIR/RawForgeCore.swiftmodule" \
    -o "$BUILD_DIR/libRawForgeCore.a" \
    "$ROOT_DIR"/Sources/RawForgeCore/*.swift

echo "[2/5] Building RawForgeApp..."
APP_SOURCES=()
while IFS= read -r -d '' f; do
    APP_SOURCES+=("$f")
done < <(find "$ROOT_DIR/Sources/RawForgeApp" -name "*.swift" -print0 | sort -z)

"$SWIFTC" "${COMMON_FLAGS[@]}" \
    -I "$MODULES_DIR" \
    "$BUILD_DIR/libRawForgeCore.a" \
    "${APP_SOURCES[@]}" \
    -o "$BIN_DIR/RawForgeApp"

echo "[3/5] Building RawForgeVerify..."
"$SWIFTC" "${COMMON_FLAGS[@]}" \
    -parse-as-library \
    -I "$MODULES_DIR" \
    "$BUILD_DIR/libRawForgeCore.a" \
    "$ROOT_DIR"/Sources/RawForgeVerify/*.swift \
    -o "$BIN_DIR/RawForgeVerify"

echo "[4/5] Packaging & ad-hoc signing dist/RawForge.app..."
rm -rf "$DIST_APP"
mkdir -p "$DIST_APP/Contents/MacOS" "$DIST_APP/Contents/Resources"
cp "$ROOT_DIR/Resources/Info.plist" "$DIST_APP/Contents/Info.plist"
cp "$ICON_FILE" "$DIST_APP/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/RawForgeApp" "$DIST_APP/Contents/MacOS/RawForgeApp"
chmod +x "$DIST_APP/Contents/MacOS/RawForgeApp"

codesign --force --deep --sign - "$DIST_APP"
codesign --verify --deep --strict "$DIST_APP"

echo "[5/5] Running automated verification suite..."
"$BIN_DIR/RawForgeVerify"

echo ""
echo "Build complete:"
echo "  App Bundle : $DIST_APP"
