#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build"
DIST="$ROOT/dist"
APP="$BUILD/SlowFast.app"
mkdir -p "$BUILD/module-cache" "$DIST"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCHITECTURES=(arm64 x86_64)
if [ -n "${ARCHS:-}" ]; then read -r -a ARCHITECTURES <<< "$ARCHS"; fi
binaries=()
for arch in "${ARCHITECTURES[@]}"; do
    case "$arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac
    mkdir -p "$BUILD/$arch"
    xcrun swiftc -swift-version 5 -O -whole-module-optimization -module-cache-path "$BUILD/module-cache" \
        -sdk "$SDK" -target "$arch-apple-macos13.0" -file-prefix-map "$ROOT=." "$ROOT"/Sources/*.swift \
        -o "$BUILD/$arch/SlowFast" -framework AppKit -framework SwiftUI -framework Security -framework ApplicationServices
    binaries+=("$BUILD/$arch/SlowFast")
done
# All deleted paths are generated bundles under this project's build directories.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/SlowFast"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/video.js" "$ROOT/Resources/使用说明.html" "$ROOT/Resources/ConnectionTest.html" "$ROOT/Resources/connection-test.mp4" "$APP/Contents/Resources/"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
ditto "$ROOT/Resources/Fonts" "$APP/Contents/Resources/Fonts"
mkdir -p "$APP/Contents/Resources/Textures"
cp "$ROOT/Resources/Textures/BrushedAluminum-v2.png" "$ROOT/Resources/Textures/BrushedAluminum-v2-prompt.txt" "$ROOT/Resources/Textures/SOURCE.txt" "$APP/Contents/Resources/Textures/"
mkdir -p "$APP/Contents/Resources/BrowserExtension" "$DIST/BrowserExtension"
cp "$ROOT"/BrowserExtension/* "$APP/Contents/Resources/BrowserExtension/"
cp "$ROOT/Resources/video.js" "$APP/Contents/Resources/BrowserExtension/video.js"
cp "$ROOT"/BrowserExtension/* "$DIST/BrowserExtension/"
cp "$ROOT/Resources/video.js" "$DIST/BrowserExtension/video.js"
# Run the original drawing source with Apple's Swift interpreter. This avoids
# first-launch signature failures of a freshly compiled standalone helper.
xcrun swift -module-cache-path "$BUILD/module-cache" "$ROOT/scripts/cassette-icon.swift" \
    "$BUILD/AppIcon.iconset" "$ROOT/Resources/Fonts/Michroma-Regular.ttf" "$ROOT/Resources/Textures/BrushedAluminum-v2.png"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$DIST/Brand"
cp "$BUILD/AppIcon.iconset/icon_512x512@2x.png" "$DIST/Brand/SlowFast-Logo-1024.png"
cp "$APP/Contents/Resources/AppIcon.icns" "$DIST/Brand/SlowFast.icns"
sign_args=(--force --sign "${SIGN_IDENTITY:--}" --entitlements "$ROOT/Resources/entitlements.plist")
if [ "${SIGN_IDENTITY:--}" != '-' ]; then sign_args+=(--options runtime --timestamp); fi
codesign "${sign_args[@]}" "$APP"
rm -rf "$DIST/SlowFast.app"
ditto "$APP" "$DIST/SlowFast.app"
codesign --verify --deep --strict "$DIST/SlowFast.app"
plutil -lint "$DIST/SlowFast.app/Contents/Info.plist"
printf 'Built: %s\n' "$DIST/SlowFast.app"
