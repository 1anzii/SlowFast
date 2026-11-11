// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import SwiftUI
import CoreText

enum SlowFastBrand {
    static let amber = Color(red: 1, green: 0.63, blue: 0.28)
    static func registerFont() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Fonts/Michroma-Regular.ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

struct CassetteDeck: View {
    let rate: Double?
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = TapeMotion()
    private var moving: Bool { playing && rate != nil && !reduceMotion }
    private struct MotionInput: Equatable {
        let rate: Double?
        let playing: Bool
    }
    private var motionInput: MotionInput { MotionInput(rate: rate, playing: moving) }

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("A").font(.system(size: 13, weight: .black)).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 2))
                Text("LOW NOISE / TYPE I").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(0.6)
                Spacer()
                Text("C–60").font(.system(size: 11, weight: .bold, design: .monospaced))
            }.foregroundStyle(Color(red: 0.22, green: 0.20, blue: 0.17))
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { _ in
                ReelWindow(angle: motion.angle(at: ProcessInfo.processInfo.systemUptime))
            }.frame(height: 76)
            HStack(spacing: 5) {
                Circle().fill(Color(white: 0.2)).frame(width: 5, height: 5)
                Rectangle().fill(Color(red: 0.68, green: 0.34, blue: 0.18)).frame(height: 3)
                Text("VARIABLE SPEED").font(.system(size: 6.5, weight: .semibold, design: .monospaced)).tracking(0.5).fixedSize()
                Rectangle().fill(Color(red: 0.68, green: 0.34, blue: 0.18)).frame(height: 3)
                Circle().fill(Color(white: 0.2)).frame(width: 5, height: 5)
            }.foregroundStyle(Color(white: 0.34))
        }.padding(.horizontal, 16).padding(.vertical, 10)
            .background(LinearGradient(colors: [Color(red: 0.91, green: 0.88, blue: 0.80), Color(red: 0.77, green: 0.75, blue: 0.69)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.65), lineWidth: 1))
            .overlay(alignment: .top) {
                Rectangle().fill(.black.opacity(0.09)).frame(height: 0.5).padding(.horizontal, 12).padding(.top, 5)
            }
            .padding(8)
            .background(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.25)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.black.opacity(0.75), lineWidth: 2))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.18), lineWidth: 1).padding(2))
            .overlay {
                LinearGradient(stops: [.init(color: .white.opacity(0.09), location: 0), .init(color: .clear, location: 0.47), .init(color: .white.opacity(0.025), location: 0.49), .init(color: .clear, location: 0.51), .init(color: .black.opacity(0.10), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 11)).padding(4).allowsHitTesting(false)
            }
            .shadow(color: .white.opacity(0.75), radius: 0, y: 1)
            .onAppear { updateMotion(motionInput) }
            // The macOS 13 onChange closure can capture the previous view value.
            // Use its new payload, with rate and play state updated together.
            .onChange(of: motionInput) { input in updateMotion(input) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("磁带舱")
            .accessibilityValue(playing ? "播放中，\(rate.map(SpeedScale.label) ?? "等待倍速")" : "磁带停转")
    }

    private func updateMotion(_ input: MotionInput) {
        motion.update(rate: input.rate, playing: input.playing, at: ProcessInfo.processInfo.systemUptime)
    }
}

private struct ReelWindow: View {
    let angle: Double
    var body: some View {
        Canvas { context, size in
            #if SLOWFAST_RENDER_TEST
            ReelFrameProbe.frames.append((ProcessInfo.processInfo.systemUptime, angle))
            #endif
            let box = CGRect(origin: .zero, size: size)
            let glass = Path(roundedRect: box, cornerRadius: 37)
            context.fill(glass, with: .linearGradient(Gradient(colors: [Color(white: 0.07), Color(white: 0.20)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(glass, with: .color(.black.opacity(0.8)), lineWidth: 2)
            let cy = size.height / 2, radius: CGFloat = 33
            let centers = [CGPoint(x: 41, y: cy), CGPoint(x: size.width - 41, y: cy)]
            var tape = Path()
            tape.move(to: CGPoint(x: centers[0].x, y: cy + 28)); tape.addLine(to: CGPoint(x: centers[1].x, y: cy + 28))
            context.stroke(tape, with: .color(Color(red: 0.38, green: 0.23, blue: 0.15)), lineWidth: 2)
            let inner = CGRect(x: size.width / 2 - 26, y: cy - 15, width: 52, height: 30)
            context.fill(Path(roundedRect: inner, cornerRadius: 4), with: .color(Color(white: 0.08)))
            for x in stride(from: inner.minX + 8, through: inner.maxX - 8, by: 9) {
                var mark = Path(); mark.move(to: CGPoint(x: x, y: cy - 6)); mark.addLine(to: CGPoint(x: x, y: cy + 6))
                context.stroke(mark, with: .color(Color(white: 0.42)), lineWidth: 1)
            }
            for (index, center) in centers.enumerated() {
                let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: disc), with: .radialGradient(Gradient(colors: [Color(red: 0.30, green: 0.23, blue: 0.18), Color(red: 0.13, green: 0.10, blue: 0.08)]), center: center, startRadius: 15, endRadius: radius))
                for r in stride(from: CGFloat(22), through: radius, by: 2) {
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.075)), lineWidth: 0.5)
                }
                var rotor = context
                rotor.translateBy(x: center.x, y: center.y)
                rotor.rotate(by: .degrees(angle + Double(index) * 32))
                let hub = CGRect(x: -21, y: -21, width: 42, height: 42)
                rotor.fill(Path(ellipseIn: hub), with: .color(Color(red: 0.86, green: 0.85, blue: 0.78)))
                rotor.stroke(Path(ellipseIn: hub), with: .color(.white.opacity(0.65)), lineWidth: 1)
                for spoke in 0..<6 {
                    var slot = rotor; slot.rotate(by: .degrees(Double(spoke) * 60))
                    slot.fill(Path(roundedRect: CGRect(x: -3.5, y: -18, width: 7, height: 9), cornerRadius: 2), with: .color(Color(white: 0.14)))
                }
                rotor.fill(Path(ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14)), with: .color(Color(white: 0.06)))
                rotor.stroke(Path(ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14)), with: .color(Color(white: 0.58)), lineWidth: 1)
                rotor.fill(Path(ellipseIn: CGRect(x: -1.5, y: -1.5, width: 3, height: 3)), with: .color(Color(white: 0.65)))
                // One witness mark makes rotation legible even at slow speeds.
                rotor.fill(Path(roundedRect: CGRect(x: -2, y: -21, width: 4, height: 3), cornerRadius: 1), with: .color(SlowFastBrand.amber))
            }
            var glint = Path(); glint.move(to: CGPoint(x: 75, y: 7)); glint.addLine(to: CGPoint(x: size.width - 75, y: 7))
            context.stroke(glint, with: .color(.white.opacity(0.13)), lineWidth: 1)
        }.accessibilityHidden(true)
    }
}

// Seven actual LED segments per digit, including dim unlit segments.
struct DigitalSpeed: View {
    let rate: Double
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(String(format: "%.2f", rate).enumerated()), id: \.offset) { _, character in
                if character == "." {
                    Circle().fill(SlowFastBrand.amber).frame(width: 4, height: 4).padding(.bottom, 1)
                } else {
                    SegmentDigit(character: character).frame(width: 23, height: 39)
                }
            }
            Text("×").font(.system(size: 15, weight: .medium, design: .monospaced)).foregroundStyle(SlowFastBrand.amber).padding(.leading, 3)
        }.shadow(color: SlowFastBrand.amber.opacity(0.22), radius: 4)
            .accessibilityElement(children: .ignore).accessibilityLabel("当前倍速").accessibilityValue(SpeedScale.label(rate))
    }
}

private struct SegmentDigit: View {
    let character: Character
    private let masks: [Character: Int] = ["0": 0x3f, "1": 0x06, "2": 0x5b, "3": 0x4f, "4": 0x66, "5": 0x6d, "6": 0x7d, "7": 0x07, "8": 0x7f, "9": 0x6f]
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 23, y: size.height / 39)
            let bars: [(CGFloat, CGFloat, Bool)] = [(4, 0, false), (19, 4, true), (19, 22, true), (4, 35, false), (0, 22, true), (0, 4, true), (4, 17.5, false)]
            for (index, bar) in bars.enumerated() {
                let rect = CGRect(x: bar.0, y: bar.1, width: bar.2 ? 4 : 15, height: bar.2 ? 13 : 4)
                let lit = (masks[character] ?? 0) & (1 << index) != 0
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(SlowFastBrand.amber.opacity(lit ? 1 : 0.055)))
            }
        }
    }
}
