// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import SwiftUI

// Exercise real SwiftUI render frames in an inactive menu-bar style panel.
// This test never accesses or controls another application.
@main struct ReelRenderingTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            print("SKIP: macOS Reduce Motion is enabled; reels should remain still.")
            return
        }
        let model = Fixture()
        let view = NSHostingView(rootView: FixtureView(model: model))
        view.frame = NSRect(x: 0, y: 0, width: 356, height: 170)
        let panel = NSPanel(contentRect: NSRect(x: 24, y: 40, width: 356, height: 170), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = view
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.close() }
        func advance(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func pixels(_ name: String) throws -> Data {
            let rect = NSRect(x: 20, y: 30, width: 316, height: 100)
            let bitmap = view.bitmapImageRepForCachingDisplay(in: rect)!
            view.cacheDisplay(in: rect, to: bitmap)
            let png = bitmap.representation(using: .png, properties: [:])!
            try png.write(to: URL(fileURLWithPath: ".build/\(name).png"))
            return png
        }
        advance(0.5)
        model.rate = 1
        model.playing = true
        advance(0.3)
        ReelFrameProbe.frames.removeAll()
        advance(0.5)
        let live = ReelFrameProbe.frames
        print("Automatic live frames after waiting → playing: \(live.count)")
        let first = try pixels("reel-playing-a")
        advance(0.35)
        let second = try pixels("reel-playing-b")
        print("Inactive application: \(!NSApp.isActive)")
        print("System reduce motion: \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)")
        print("Playing frames differ: \(first != second)")
        model.playing = false
        advance(0.3)
        let pausedA = try pixels("reel-paused-a")
        advance(0.35)
        let pausedB = try pixels("reel-paused-b")
        print("Paused frames identical: \(pausedA == pausedB)")
        guard first != second, pausedA == pausedB, live.count > 5,
              let start = live.first, let end = live.last, abs(end.1 - start.1) > 5 else { exit(1) }
        func sample(_ rate: Double) throws {
            model.rate = rate; model.playing = true
            advance(0.15)
            ReelFrameProbe.frames.removeAll()
            advance(0.4)
            let frames = ReelFrameProbe.frames
            guard frames.count >= 5, let a = frames.first, let b = frames.last, b.0 > a.0 else {
                print("FAIL: no continuous drawing at \(rate)x"); exit(1)
            }
            let delta = (b.1 - a.1 + 360).truncatingRemainder(dividingBy: 360)
            let degreesPerSecond = delta / (b.0 - a.0)
            guard abs(degreesPerSecond - rate * 75) < 3 else {
                print("FAIL: expected \(rate * 75)°/s, rendered \(degreesPerSecond)°/s"); exit(1)
            }
            print(String(format: "PASS: %.2fx renders %.1f°/s in inactive panel", rate, degreesPerSecond))
        }
        for rate in SpeedScale.values { try sample(rate) }
        model.rate = nil
        advance(0.15)
        let unknownA = try pixels("reel-unknown-a")
        advance(0.35)
        guard try unknownA == pixels("reel-unknown-b") else { print("FAIL: unknown rate must stop the reel"); exit(1) }
        try sample(1)
        print("PASS: waiting → playing, pause → resume, all six rendered speeds, unknown → known")
    }
}
enum ReelFrameProbe {
    static var frames: [(Double, Double)] = []
}
private final class Fixture: ObservableObject {
    @Published var playing = false
    @Published var rate: Double? = nil
}
private struct FixtureView: View {
    @ObservedObject var model: Fixture
    var body: some View {
        CassetteDeck(rate: model.rate, playing: model.playing)
            .frame(width: 356, height: 170)
    }
}
