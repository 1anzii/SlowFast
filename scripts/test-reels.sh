#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/module-cache
xcrun swiftc -D SLOWFAST_RENDER_TEST -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path .build/module-cache \
  Sources/Core.swift Sources/CassetteDesign.swift Tests/ReelRenderingTests.swift \
  -o .build/reel-render-tests -framework AppKit -framework SwiftUI
.build/reel-render-tests
