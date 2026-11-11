#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/module-cache"
xcrun swiftc -swift-version 5 -module-cache-path "$ROOT/.build/module-cache" \
  "$ROOT/Sources/Core.swift" "$ROOT/Sources/LocalAdapters.swift" "$ROOT/Sources/ConfigEditing.swift" "$ROOT/Tests/CoreTests.swift" \
  -o "$ROOT/.build/core-tests" -framework Security
python3 "$ROOT/Tests/protocols.py" "$ROOT/.build/core-tests"
node --check "$ROOT/Resources/video.js"
node --check "$ROOT/BrowserExtension/background.js"
node --check "$ROOT/BrowserExtension/popup.js"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=640x360:rate=30' \
  -t 8 -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$ROOT/.build/test-video.mp4"
node "$ROOT/Tests/browser.cjs"
