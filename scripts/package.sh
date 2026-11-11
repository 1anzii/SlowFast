#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${PACKAGE_APP:-$ROOT/dist/SlowFast.app}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DIST="$ROOT/dist"
STAGE="$ROOT/.build/package-$VERSION"
BASE="$DIST/SlowFast-$VERSION-mac"
codesign --verify --deep --strict "$APP"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/SlowFast.app"
ln -sfn /Applications "$STAGE/Applications"
cp "$ROOT/Resources/安装说明.txt" "$STAGE/安装说明.txt"
cp "$ROOT/Resources/使用说明.html" "$STAGE/使用说明.html"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BASE.zip"
hdiutil create -volname 'SlowFast' -srcfolder "$STAGE" -ov -fs HFS+ -format UDZO "$BASE.dmg"
(cd "$DIST" && shasum -a 256 "SlowFast-$VERSION-mac.zip" "SlowFast-$VERSION-mac.dmg" > "SlowFast-$VERSION-SHA256.txt")
printf 'Packaged: %s.dmg\n' "$BASE"
