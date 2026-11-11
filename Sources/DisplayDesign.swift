// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import SwiftUI

// Smoked glass in a recessed metal bezel; the illuminated content sits below
// the reflections, rather than looking like text painted on a black rectangle.
struct TapeDisplay: View {
    let rate: Double?
    let word: String
    let target: String
    let status: String
    let playing: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PLAYBACK / ×").font(.system(size: 6, weight: .medium, design: .monospaced)).tracking(1.3)
                    .foregroundStyle(SlowFastBrand.amber.opacity(0.34))
                Group {
                    if let rate { DigitalSpeed(rate: rate) }
                    else if word == "READY" { ReadySignal() }
                    else { DotMatrixWord(word: word, brightness: 0.85) }
                }.frame(width: 117, height: 36, alignment: .leading)
            }
            Rectangle().fill(SlowFastBrand.amber.opacity(0.12)).frame(width: 0.7, height: 37)
            VStack(alignment: .leading, spacing: 7) {
                Text(target).font(.system(size: 10, weight: .medium, design: .monospaced)).lineLimit(1)
                    .foregroundStyle(Color(red: 0.81, green: 0.76, blue: 0.63))
                HStack(spacing: 5) {
                    Image(systemName: playing ? "play.fill" : "circle.fill").font(.system(size: playing ? 7 : 4, weight: .medium))
                    Text(status).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(0.6).lineLimit(1)
                }.foregroundStyle(SlowFastBrand.amber.opacity(playing ? 0.85 : 0.5))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 17).frame(height: 72)
            .background {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.025, green: 0.033, blue: 0.030), Color(red: 0.075, green: 0.085, blue: 0.068)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [SlowFastBrand.amber.opacity(0.055), .clear], center: .leading, startRadius: 2, endRadius: 190)
                    ScreenMesh().opacity(0.40)
                }.clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .overlay {
                GeometryReader { proxy in
                    Path { path in
                        let w = proxy.size.width, h = proxy.size.height
                        path.move(to: .zero); path.addLine(to: CGPoint(x: w * 0.69, y: 0))
                        path.addLine(to: CGPoint(x: w * 0.43, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.closeSubpath()
                    }.fill(LinearGradient(colors: [.white.opacity(0.11), .white.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                }.clipShape(RoundedRectangle(cornerRadius: 6)).allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 1).fill(LinearGradient(colors: [.clear, .white.opacity(0.25), .white.opacity(0.04), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1).padding(.horizontal, 10).padding(.top, 3).allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.95), lineWidth: 2))
            .padding(3)
            .background(LinearGradient(stops: [.init(color: Color(white: 0.15), location: 0), .init(color: Color(white: 0.30), location: 0.4), .init(color: Color(white: 0.80), location: 0.92), .init(color: Color(white: 0.52), location: 1)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.6), lineWidth: 0.6))
            .shadow(color: .white.opacity(0.65), radius: 0, y: 0.8)
    }
}

private struct ScreenMesh: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: CGFloat(0), to: size.height, by: 2) {
                var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.black.opacity(0.22)), lineWidth: 0.5)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ReadySignal: View {
    var animationEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = ProcessInfo.processInfo.systemUptime
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || !animationEnabled)) { _ in
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let brightness = reduceMotion || !animationEnabled ? 1 : 0.22 + 0.78 * (0.5 + 0.5 * cos(elapsed * .pi * 2 / 1.8))
            DotMatrixWord(word: "READY", brightness: brightness)
        }.accessibilityElement(children: .ignore).accessibilityLabel("READY，等待视频")
    }
}

struct DotMatrixWord: View {
    let word: String
    let brightness: Double
    private static let glyphs: [Character: [String]] = [
        "R": ["11110","10001","10001","11110","10100","10010","10001"],
        "E": ["11111","10000","10000","11110","10000","10000","11111"],
        "A": ["01110","10001","10001","11111","10001","10001","10001"],
        "D": ["11110","10001","10001","10001","10001","10001","11110"],
        "Y": ["10001","10001","01010","00100","00100","00100","00100"],
        "O": ["01110","10001","10001","10001","10001","10001","01110"],
        "F": ["11111","10000","10000","11110","10000","10000","10000"],
        "C": ["01111","10000","10000","10000","10000","10000","01111"],
        "H": ["10001","10001","10001","11111","10001","10001","10001"],
        "K": ["10001","10010","10100","11000","10100","10010","10001"]
    ]
    var body: some View {
        Canvas { context, size in
            #if SLOWFAST_DISPLAY_TEST
            if word == "READY" { DisplayFrameProbe.frames.append((ProcessInfo.processInfo.systemUptime, brightness)) }
            #endif
            let pitch: CGFloat = 3.2, dot: CGFloat = 2.15
            let top = (size.height - 7 * pitch) / 2
            for (letter, character) in word.enumerated() {
                guard let rows = Self.glyphs[character] else { continue }
                for (row, line) in rows.enumerated() {
                    for (column, bit) in line.enumerated() {
                        let rect = CGRect(x: CGFloat(letter) * 23 + CGFloat(column) * pitch, y: top + CGFloat(row) * pitch, width: dot, height: dot)
                        context.fill(Path(roundedRect: rect, cornerRadius: 0.5), with: .color(SlowFastBrand.amber.opacity(bit == "1" ? brightness : 0.045)))
                    }
                }
            }
        }.frame(width: 117, height: 36)
            .shadow(color: SlowFastBrand.amber.opacity(brightness * 0.30), radius: 3)
            .accessibilityLabel(word)
    }
}
