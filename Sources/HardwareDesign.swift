// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import SwiftUI

enum DeckMaterials {
    // The preview harness can supply the same resource before constructing views.
    static var wornMetal: NSImage? = Bundle.main.url(forResource: "BrushedAluminum-v2", withExtension: "png", subdirectory: "Textures").flatMap(NSImage.init(contentsOf:))
}

struct WornMetalCase: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.68), .white, Color(white: 0.32), Color(white: 0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack {
                Color(white: 0.76)
                if let texture = DeckMaterials.wornMetal {
                    Image(nsImage: texture).resizable().saturation(0)
                }
                LinearGradient(stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .clear, location: 0.35), .init(color: .black.opacity(0.08), location: 0.7), .init(color: .white.opacity(0.10), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }.clipShape(RoundedRectangle(cornerRadius: 19)).padding(3)
        }
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.black.opacity(0.7), lineWidth: 0.8))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.7), lineWidth: 1).padding(1.5))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black.opacity(0.18), lineWidth: 0.6).padding(4))
        .accessibilityHidden(true)
    }
}

// Separate machined key caps: bright top bevel, solid side wall, recessed socket.
// The label stays crisp when unavailable; the screen explains the waiting state.
struct TransportKeyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        return configuration.label
            .foregroundStyle(Color(white: enabled ? 0.13 : 0.30))
            .frame(maxWidth: .infinity).frame(height: 59)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Color(white: 0.47), Color(white: 0.23)], startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.30)).frame(height: 0.7).padding(.horizontal, 4).padding(.bottom, 1) }
                        .offset(y: down ? 2 : 7)
                    RoundedRectangle(cornerRadius: 4).fill(LinearGradient(stops: [
                        .init(color: Color(white: 0.99), location: 0),
                        .init(color: Color(white: 0.63), location: 0.06),
                        .init(color: Color(white: 0.91), location: 0.12),
                        .init(color: Color(white: 0.77), location: 0.50),
                        .init(color: Color(white: 0.67), location: 0.92),
                        .init(color: Color(white: 0.39), location: 1)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [Color(white: 0.90), Color(white: 0.76), Color(white: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(3)
                    MachinedGrain().clipShape(RoundedRectangle(cornerRadius: 2)).padding(3)
                    RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.65), lineWidth: 0.7).padding(0.7)
                    RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.72), lineWidth: 0.7)
                }
            }
            .shadow(color: .black.opacity(down ? 0.20 : 0.65), radius: down ? 0.5 : 2.2, x: 0, y: down ? 1 : 5)
            .offset(y: down ? 5 : 0).padding(.bottom, 7)
    }
}

private struct MachinedGrain: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<150 {
                let y = CGFloat(i) * size.height / 150
                let start = CGFloat((i * 43) % 97) / 97 * size.width
                var line = Path(); line.move(to: CGPoint(x: start, y: y))
                line.addLine(to: CGPoint(x: min(size.width, start + CGFloat(12 + i % 43)), y: y))
                context.stroke(line, with: .color((i % 3 == 0 ? Color.black : .white).opacity(i % 5 == 0 ? 0.10 : 0.045)), lineWidth: 0.3)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct HardwareScrew: View {
    var body: some View {
        Circle().fill(LinearGradient(colors: [Color(white: 0.47), Color(white: 0.89), Color(white: 0.53)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().strokeBorder(.black.opacity(0.50), lineWidth: 0.7))
            .overlay(Capsule().fill(Color(white: 0.22)).frame(width: 6, height: 1.3).shadow(color: .white.opacity(0.7), radius: 0, y: 0.6).rotationEffect(.degrees(-30)))
            .frame(width: 10, height: 10).shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.7)
            .accessibilityHidden(true)
    }
}

struct HardwareLED: View {
    let on: Bool
    var warning = false
    private var light: Color { warning ? Color(red: 0.96, green: 0.50, blue: 0.18) : Color(red: 0.56, green: 0.76, blue: 0.30) }
    var body: some View {
        Circle().fill(Color(white: 0.15)).frame(width: 10, height: 10)
            .overlay(Circle().fill(RadialGradient(colors: on ? [.white.opacity(0.90), light, light.opacity(0.55)] : [Color(white: 0.40), Color(white: 0.24)], center: .topLeading, startRadius: 0, endRadius: 6)).padding(2))
            .overlay(Circle().strokeBorder(.white.opacity(0.44), lineWidth: 0.7))
            .shadow(color: on ? light.opacity(0.35) : .clear, radius: 3)
            .accessibilityHidden(true)
    }
}

struct HardwareKeyStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, compact ? 11 : 9).padding(.vertical, compact ? 8 : 12)
            .foregroundStyle(Color(white: enabled ? 0.16 : 0.42))
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.33)).offset(y: 3)
                    RoundedRectangle(cornerRadius: 4).fill(LinearGradient(stops: [
                        .init(color: Color(white: configuration.isPressed ? 0.63 : 0.94), location: 0),
                        .init(color: Color(white: 0.80), location: 0.15),
                        .init(color: Color(white: 0.68), location: 0.82),
                        .init(color: Color(white: 0.86), location: 1)
                    ], startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(configuration.isPressed ? 0.3 : 0.8), lineWidth: 0.7).padding(1)
                    RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.5), lineWidth: 0.6)
                }
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.1 : 0.40), radius: configuration.isPressed ? 0.3 : 1.2, x: 0, y: configuration.isPressed ? 0 : 2)
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

struct MechanicalPowerSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [Color(white: 0.14), Color(white: 0.30)], startPoint: .top, endPoint: .bottom))
                HStack {
                    Text("ON").foregroundStyle(isOn ? SlowFastBrand.amber : Color(white: 0.48))
                    Spacer()
                    Text("OFF").foregroundStyle(Color(white: 0.48))
                }.font(.system(size: 9, weight: .bold, design: .monospaced)).padding(.horizontal, 13)
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(stops: [.init(color: Color(white: 0.93), location: 0), .init(color: Color(white: 0.66), location: 0.25), .init(color: Color(white: 0.83), location: 0.78), .init(color: Color(white: 0.53), location: 1)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.7), lineWidth: 1).padding(1))
                    .overlay {
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 0.5).fill(Color(white: 0.35)).frame(width: 1.2, height: 24).shadow(color: .white.opacity(0.85), radius: 0, x: 1, y: 0)
                            }
                        }
                    }
                    .frame(width: 58, height: 40)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: isOn ? -2 : 2, y: 1.5)
                    .offset(x: isOn ? 34 : -34)
                    .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85), value: isOn)
            }.frame(width: 136, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.black.opacity(0.9), lineWidth: 1.4))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.65), lineWidth: 0.8).padding(-1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("Fn 快捷键总开关")
            .accessibilityValue(isOn ? "已开启" : "已关闭")
            .help(isOn ? "点击暂停 Fn 快捷键" : "点击开启 Fn 快捷键")
    }
}

struct VentGrille: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { _ in
                Capsule().fill(Color(white: 0.29)).frame(width: 2, height: 13).shadow(color: .white.opacity(0.7), radius: 0, x: 0.5, y: 0.5)
            }
        }.accessibilityHidden(true)
    }
}
