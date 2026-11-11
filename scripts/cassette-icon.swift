// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import CoreText

// Original cassette-player artwork; the unmodified Michroma font is SIL OFL 1.1.
let folder = CommandLine.arguments[1]
let paintTexture = CommandLine.arguments.count > 3 ? NSImage(contentsOfFile: CommandLine.arguments[3]) : nil
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, .process, nil)
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
func grey(_ x: CGFloat) -> NSColor { NSColor(white: x, alpha: 1) }
let amber = NSColor(calibratedRed: 0.94, green: 0.56, blue: 0.23, alpha: 1)
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}
func gradient(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) { NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90) }
func stroke(_ path: NSBezierPath, _ color: NSColor, _ width: CGFloat) { color.setStroke(); path.lineWidth = width; path.stroke() }
func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, brand: Bool = false) {
    let font = brand ? NSFont(name: "Michroma-Regular", size: size) ?? .systemFont(ofSize: size, weight: .bold) : .monospacedSystemFont(ofSize: size, weight: .semibold)
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
}
func drawIcon(_ size: CGFloat) {
    let transform = NSAffineTransform(); transform.scale(by: size / 1024); transform.concat()
    let body = rounded(60, 60, 904, 904, 188)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.set()
    grey(0.4).setFill(); body.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGradient(colorsAndLocations: (grey(0.95), 0), (grey(0.80), 0.25), (grey(0.70), 0.66), (grey(0.88), 1))!.draw(in: body, angle: -75)
    NSGraphicsContext.saveGraphicsState(); body.addClip()
    paintTexture?.draw(in: NSRect(x: 60, y: 60, width: 904, height: 904), from: .zero, operation: .sourceOver, fraction: 0.92)
    for y in stride(from: 60, to: 965, by: 2) {
        let line = NSBezierPath(); line.move(to: NSPoint(x: 60, y: y)); line.line(to: NSPoint(x: 964, y: y))
        stroke(line, NSColor.black.withAlphaComponent(y % 8 == 0 ? 0.055 : 0.018), 0.6)
    }
    for i in 0..<160 {
        let x = CGFloat(82 + (i * 137) % 858), y = CGFloat(79 + (i * 211) % 864)
        if x > 126 && x < 897 && y > 126 && y < 898 { continue }
        let line = NSBezierPath(); line.move(to: NSPoint(x: x, y: y)); line.line(to: NSPoint(x: x + CGFloat(6 + i % 20), y: y + 2))
        stroke(line, (i % 2 == 0 ? NSColor.white : NSColor.black).withAlphaComponent(0.15), 1)
    }
    NSGraphicsContext.restoreGraphicsState()
    stroke(body, .white.withAlphaComponent(0.85), 5)
    stroke(rounded(67, 67, 890, 890, 182), grey(0.48), 2)
    label("SLOWFAST", x: 173, y: 809, size: 57, color: .white.withAlphaComponent(0.7), brand: true)
    label("SLOWFAST", x: 173, y: 812, size: 57, color: grey(0.18), brand: true)
    label("CASSETTE SPEED CONTROL", x: 179, y: 776, size: 18, color: grey(0.38))
    let door = rounded(132, 384, 760, 362, 37)
    gradient(door, grey(0.10), grey(0.27)); stroke(door, grey(0.05), 6)
    stroke(rounded(139, 391, 746, 348, 30), grey(0.51), 2)
    let shell = rounded(159, 408, 706, 314, 21)
    gradient(shell, NSColor(calibratedRed: 0.91, green: 0.88, blue: 0.79, alpha: 1), NSColor(calibratedRed: 0.74, green: 0.72, blue: 0.65, alpha: 1)); stroke(shell, .white.withAlphaComponent(0.6), 2)
    label("A", x: 184, y: 661, size: 28, color: grey(0.22))
    label("STEREO", x: 231, y: 667, size: 17, color: grey(0.3))
    label("C–60", x: 756, y: 665, size: 20, color: grey(0.22))
    let glass = rounded(188, 454, 648, 190, 90)
    gradient(glass, grey(0.07), grey(0.20)); stroke(glass, grey(0.05), 3)
    let tape = NSBezierPath(); tape.move(to: NSPoint(x: 290, y: 477)); tape.line(to: NSPoint(x: 734, y: 477)); stroke(tape, NSColor(calibratedRed: 0.38, green: 0.24, blue: 0.15, alpha: 1), 5)
    for x: CGFloat in [291, 733] {
        let reel = NSBezierPath(ovalIn: NSRect(x: x - 83, y: 466, width: 166, height: 166))
        gradient(reel, NSColor(calibratedRed: 0.28, green: 0.22, blue: 0.17, alpha: 1), grey(0.10))
        for r in stride(from: CGFloat(56), through: CGFloat(83), by: 5) { stroke(NSBezierPath(ovalIn: NSRect(x: x - r, y: 549 - r, width: r * 2, height: r * 2)), .white.withAlphaComponent(0.09), 1) }
        let hub = NSBezierPath(ovalIn: NSRect(x: x - 55, y: 494, width: 110, height: 110))
        gradient(hub, grey(0.94), NSColor(calibratedRed: 0.70, green: 0.70, blue: 0.64, alpha: 1)); stroke(hub, .white.withAlphaComponent(0.75), 2)
        for i in 0..<6 {
            NSGraphicsContext.saveGraphicsState()
            let rotate = NSAffineTransform(); rotate.translateX(by: x, yBy: 549); rotate.rotate(byDegrees: CGFloat(i * 60) + (x < 512 ? 12 : 42)); rotate.concat()
            grey(0.13).setFill(); rounded(-8, 27, 16, 22, 5).fill(); NSGraphicsContext.restoreGraphicsState()
        }
        let axis = NSBezierPath(ovalIn: NSRect(x: x - 17, y: 532, width: 34, height: 34)); grey(0.08).setFill(); axis.fill(); stroke(axis, grey(0.6), 3)
        grey(0.63).setFill(); NSBezierPath(ovalIn: NSRect(x: x - 4, y: 545, width: 8, height: 8)).fill()
    }
    gradient(rounded(435, 512, 154, 76, 10), grey(0.09), grey(0.13))
    for x in stride(from: 459, through: 567, by: 27) { let mark = NSBezierPath(); mark.move(to: NSPoint(x: x, y: 535)); mark.line(to: NSPoint(x: x, y: 566)); stroke(mark, grey(0.48), 2) }
    amber.setFill(); rounded(190, 428, 644, 6, 2).fill()
    gradient(rounded(153, 287, 399, 72, 12), grey(0.08), grey(0.18))
    label("1.00 ×", x: 216, y: 291, size: 48, color: amber)
    label("PLAY", x: 653, y: 305, size: 24, color: grey(0.28))
    let lamp = NSBezierPath(ovalIn: NSRect(x: 787, y: 310, width: 21, height: 21)); gradient(lamp, NSColor(calibratedRed: 0.72, green: 0.82, blue: 0.49, alpha: 1), NSColor(calibratedRed: 0.25, green: 0.4, blue: 0.21, alpha: 1)); stroke(lamp, grey(0.3), 2)
    gradient(rounded(143, 135, 738, 132, 20), grey(0.12), grey(0.32))
    for index in 0..<3 {
        let x = CGFloat(155 + index * 241), key = rounded(CGFloat(155 + index * 241), 163, 230, 95, 8)
        gradient(rounded(x, 143, 230, 105, 8), grey(0.50), grey(0.25))
        gradient(key, grey(0.99), grey(0.48)); stroke(key, .white.withAlphaComponent(0.8), 2)
        gradient(rounded(x + 6, 169, 218, 83, 4), grey(0.89), grey(0.74))
        grey(0.18).setFill()
        if index == 1 { label("1×", x: x + 77, y: 174, size: 41, color: grey(0.20)) }
        else {
            for shift: CGFloat in [-19, 19] {
                let cx = x + 115 + shift, sign: CGFloat = index == 0 ? -1 : 1
                let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: cx + sign * 17, y: 203)); arrow.line(to: NSPoint(x: cx - sign * 15, y: 225)); arrow.line(to: NSPoint(x: cx - sign * 15, y: 181)); arrow.close(); arrow.fill()
            }
        }
    }
    for p in [NSPoint(x: 123, y: 847), NSPoint(x: 901, y: 847), NSPoint(x: 124, y: 123), NSPoint(x: 900, y: 123)] {
        let screw = NSBezierPath(ovalIn: NSRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)); gradient(screw, grey(0.96), grey(0.54)); stroke(screw, grey(0.5), 1)
        let slot = NSBezierPath(); slot.move(to: NSPoint(x: p.x - 6, y: p.y - 4)); slot.line(to: NSPoint(x: p.x + 6, y: p.y + 4)); stroke(slot, grey(0.30), 2)
    }
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        drawIcon(CGFloat(pixels)); NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
    }
}
