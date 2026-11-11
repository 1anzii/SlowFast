// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import CoreGraphics

enum SpeedAction: String {
    case slower, faster, reset, set
}

enum SpeedScale {
    static let values: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    static func next(_ current: Double, action: SpeedAction, requested: Double? = nil) -> Double {
        let rate = current.isFinite && current > 0 ? current : 1
        switch action {
        case .slower: return values.last(where: { $0 < rate - 0.001 }) ?? values[0]
        case .faster: return values.first(where: { $0 > rate + 0.001 }) ?? values.last!
        case .reset: return 1
        case .set: return values.contains(requested ?? -1) ? requested! : 1
        }
    }
    static func label(_ rate: Double) -> String { String(format: "%g×", rate) }
}

enum HotKey {
    static func action(keyCode: Int64, flags: CGEventFlags) -> SpeedAction? {
        guard flags.contains(.maskSecondaryFn),
              flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { return nil }
        switch keyCode {
        case 43 where !flags.contains(.maskShift): return .slower
        case 47 where !flags.contains(.maskShift): return .faster
        case 44: return .reset // '/' and '?' share a physical key.
        default: return nil
        }
    }
}

struct ControlResult {
    let rate: Double?
    let message: String
    var isPlaying: Bool? = nil
}

struct PlaybackSnapshot {
    let rate: Double?
    let isPlaying: Bool
}

// Integrate motion when the speed changes, so changing speed never jumps a reel.
struct TapeMotion {
    private var phase = 0.0
    private var updatedAt = 0.0
    private var speed = 0.0
    func angle(at time: TimeInterval) -> Double {
        (phase + max(0, time - updatedAt) * speed * 75).truncatingRemainder(dividingBy: 360)
    }
    mutating func update(rate: Double?, playing: Bool, at time: TimeInterval) {
        phase = angle(at: time)
        updatedAt = time
        speed = playing && rate?.isFinite == true ? max(0, min(rate ?? 0, 16)) : 0
    }
}

struct SlowFastError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct AppleScriptFailure: LocalizedError {
    let number: Int
    let detail: String
    var errorDescription: String? {
        if number == -1743 || number == -1744 { return "请在系统自动化设置中允许 SlowFast 控制此播放器" }
        if number == -1712 { return "播放器未及时响应，请关闭弹窗后重试" }
        return "播放器错误（\(number)）：\(detail)"
    }
}

enum BrowserConnection: Equatable {
    case unchecked, checking, ready, automation, javascript, noPage, confirmation
    case notInstalled, notRunning, noMedia, localSetup, extensionManual
    case failed(String)

    var title: String {
        switch self {
        case .unchecked: return "尚未检查"
        case .checking: return "正在检查…"
        case .ready: return "已连接"
        case .automation: return "需要允许自动化控制"
        case .javascript: return "需要开启浏览器脚本控制"
        case .noPage: return "请先打开一个网页"
        case .confirmation: return "请在浏览器中点「允许」"
        case .notInstalled: return "未安装"
        case .notRunning: return "尚未打开"
        case .noMedia: return "已连接 · 等待视频"
        case .localSetup: return "需要连接本地接口"
        case .extensionManual: return "扩展模式 · 请在视频页验证"
        case .failed: return "连接未完成"
        }
    }

    var needsSetup: Bool {
        switch self { case .automation, .javascript, .confirmation, .localSetup, .failed: return true; default: return false }
    }

    var connected: Bool { self == .ready || self == .noMedia }
    var actionTitle: String {
        switch self {
        case .notInstalled: return "官网"
        case .notRunning, .noPage: return "连接"
        case .checking: return "检查中"
        case .confirmation: return "继续"
        case .automation, .javascript, .localSetup, .failed: return "修复"
        case .extensionManual: return "说明"
        default: return "检查"
        }
    }

    static func classify(number: Int, detail: String) -> BrowserConnection {
        if number == -1743 || number == -1744 { return .automation }
        if number == -2700 && detail.contains("SLOWFAST_NO_PAGE") { return .noPage }
        let normalized = detail.lowercased().filter { !$0.isWhitespace }
        // Match the browser's permission error, never arbitrary JavaScript exceptions.
        if (number == 8 || number == 12) &&
            (normalized.contains("allowjavascriptfromappleevents") ||
             normalized.contains("javascript的功能已关闭") ||
             normalized.contains("javascriptthroughapplescriptisturnedoff")) { return .javascript }
        return .failed(detail)
    }
}

struct PlayerChoice: Identifiable {
    enum Kind { case browser, quickTime, iina, mpv, vlc }
    let id: String
    let name: String
    let kind: Kind
    let website: String
    var isBrowser: Bool { kind == .browser }
    static let all: [PlayerChoice] = [
        .init(id: "com.google.Chrome", name: "Chrome", kind: .browser, website: "https://www.google.com/chrome/"),
        .init(id: "com.apple.Safari", name: "Safari", kind: .browser, website: "https://www.apple.com/safari/"),
        .init(id: "com.apple.QuickTimePlayerX", name: "QuickTime", kind: .quickTime, website: "https://support.apple.com/quicktime"),
        .init(id: "com.microsoft.edgemac", name: "Edge", kind: .browser, website: "https://www.microsoft.com/edge"),
        .init(id: "com.brave.Browser", name: "Brave", kind: .browser, website: "https://brave.com/"),
        .init(id: "com.vivaldi.Vivaldi", name: "Vivaldi", kind: .browser, website: "https://vivaldi.com/"),
        .init(id: "company.thebrowser.Browser", name: "Arc", kind: .browser, website: "https://arc.net/"),
        .init(id: "com.colliderli.iina", name: "IINA", kind: .iina, website: "https://iina.io/"),
        .init(id: "org.videolan.vlc", name: "VLC", kind: .vlc, website: "https://www.videolan.org/vlc/"),
        .init(id: "io.mpv", name: "mpv", kind: .mpv, website: "https://mpv.io/installation/"),
        .init(id: "com.google.Chrome.beta", name: "Chrome Beta", kind: .browser, website: "https://www.google.com/chrome/beta/"),
        .init(id: "com.google.Chrome.canary", name: "Chrome Canary", kind: .browser, website: "https://www.google.com/chrome/canary/"),
        .init(id: "com.apple.SafariTechnologyPreview", name: "Safari Preview", kind: .browser, website: "https://developer.apple.com/safari/technology-preview/")
    ]
}

enum SupportedApp {
    static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi", "company.thebrowser.Browser"
    ]
    static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static func supports(_ id: String) -> Bool {
        chromium.contains(id) || safari.contains(id) || ["com.apple.QuickTimePlayerX", "org.videolan.vlc", "com.colliderli.iina", "io.mpv"].contains(id)
    }
}
