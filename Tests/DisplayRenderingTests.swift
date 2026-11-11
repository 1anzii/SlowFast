// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import SwiftUI

// Observe real native render frames, including transitions away from READY.
// No keyboard synthesis, player access, or UI automation of other applications.
@main struct DisplayRenderingTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            print("SKIP: system Reduce Motion enabled; READY must remain steady."); return
        }
        let model = DisplayFixture()
        let host = NSHostingView(rootView: DisplayFixtureView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 356, height: 78)
        let panel = NSPanel(contentRect: NSRect(x: 24, y: 40, width: 356, height: 78), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.contentView = host; panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.close() }
        func advance(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func pixels() -> Data {
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])!
        }
        func checkBlink(_ title: String) {
            DisplayFrameProbe.frames.removeAll(); advance(2)
            let values = DisplayFrameProbe.frames.map(\.1)
            guard values.count > 10, let lo = values.min(), let hi = values.max(), hi - lo > 0.65 else {
                fatalError("READY failed to animate: \(title)")
            }
            print("PASS: \(title), \(values.count) live frames, brightness \(String(format: "%.2f…%.2f", lo, hi))")
        }
        advance(0.2); checkBlink("READY blinks in inactive native panel")
        model.rate = 1.25; advance(0.2); DisplayFrameProbe.frames.removeAll()
        let speedA = pixels(); advance(0.4); let speedB = pixels()
        assert(speedA == speedB && DisplayFrameProbe.frames.isEmpty, "Numeric speed must not blink")
        print("PASS: READY → speed stops blinking; numeric pixels remain stable")
        model.rate = nil; advance(0.2); checkBlink("speed → READY resumes blinking")
        model.reduceMotion = true; advance(0.2); DisplayFrameProbe.frames.removeAll()
        let stillA = pixels(); advance(0.4); let stillB = pixels()
        assert(stillA == stillB && DisplayFrameProbe.frames.allSatisfy { $0.1 == 1 }, "Reduce Motion must be steady and bright")
        print("PASS: disabled animation keeps READY fully lit and static (same pause path as Reduce Motion)")
        model.reduceMotion = false; model.word = "OFF"; advance(0.2); DisplayFrameProbe.frames.removeAll()
        let offA = pixels(); advance(0.4); let offB = pixels()
        assert(offA == offB && DisplayFrameProbe.frames.isEmpty, "OFF must not run READY animation")
        print("PASS: OFF remains static; inactive application: \(!NSApp.isActive)")
    }
}
enum DisplayFrameProbe { static var frames: [(Double, Double)] = [] }
private final class DisplayFixture: ObservableObject {
    @Published var rate: Double? = nil
    @Published var word = "READY"
    @Published var reduceMotion = false
}
private struct DisplayFixtureView: View {
    @ObservedObject var model: DisplayFixture
    var body: some View {
        if model.reduceMotion {
            ReadySignal(animationEnabled: false).frame(width: 356, height: 78)
        } else {
            TapeDisplay(rate: model.rate, word: model.word, target: "Google Chrome", status: model.rate == nil ? "STANDBY" : "PLAY", playing: model.rate != nil)
        }
    }
}
