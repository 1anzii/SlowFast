// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import SwiftUI
import CoreText

// Offscreen rendering of our own views; no UI automation and no live player access.
@main struct VisualPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        CTFontManagerRegisterFontsForURL(root.appendingPathComponent("Resources/Fonts/Michroma-Regular.ttf") as CFURL, .process, nil)
        DeckMaterials.wornMetal = NSImage(contentsOf: root.appendingPathComponent("Resources/Textures/BrushedAluminum-v2.png"))
        let model = AppModel()
        model.hotKeysReady = true; model.accessibilityReady = true
        model.targetName = "Google Chrome"; model.targetBundleID = "com.google.Chrome"; model.targetSupported = true
        model.rate = 1.25; model.playbackKnown = true; model.playbackPlaying = true
        model.installedIDs = ["com.google.Chrome", "com.apple.Safari", "com.apple.QuickTimePlayerX"]
        for id in model.installedIDs { model.browserConnections[id] = .ready }
        func save<V: View>(_ view: V, size: NSSize, name: String) throws {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(".build/\(name).png"))
        }
        try save(SettingsView(model: model), size: NSSize(width: 400, height: 568), name: "cassette-preview")
        try save(SettingsView(model: model, connectionsOpen: true), size: NSSize(width: 400, height: 568), name: "connections-preview")
        try save(PreferencesView(model: model, viewportSize: NSSize(width: 420, height: 580)), size: NSSize(width: 420, height: 580), name: "preferences-preview")
        model.rate = nil; model.playbackKnown = false; model.playbackPlaying = false
        try save(SettingsView(model: model), size: NSSize(width: 400, height: 568), name: "cassette-idle-preview")
        model.enabled = false
        try save(SettingsView(model: model), size: NSSize(width: 400, height: 568), name: "cassette-off-preview")
        model.enabled = true; model.hotKeysReady = false; model.browserConnections["com.google.Chrome"] = .javascript
        try save(SettingsView(model: model, connectionsOpen: true), size: NSSize(width: 400, height: 568), name: "connections-repair-preview")
    }
}
