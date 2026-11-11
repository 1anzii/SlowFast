#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/module-cache
sources=()
for source in Sources/*.swift; do
  if [ "$source" != 'Sources/main.swift' ]; then sources+=("$source"); fi
done
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" -module-cache-path .build/module-cache \
  "${sources[@]}" Tests/VisualPreview.swift -o .build/visual-preview \
  -framework AppKit -framework SwiftUI -framework Security -framework ApplicationServices
.build/visual-preview
