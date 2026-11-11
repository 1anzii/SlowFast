// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import CoreServices

enum ConnectionProbe {
    // Read only; called while the deck is visible. Never request new permission here.
    static func playback(_ player: PlayerChoice, socket: String, port: Int) throws -> PlaybackSnapshot {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: player.id).contains(where: { !$0.isTerminated }) else { throw SlowFastError("播放器已退出") }
        if player.isBrowser || player.kind == .quickTime {
            let target = NSAppleEventDescriptor(bundleIdentifier: player.id)
            guard AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr else { throw SlowFastError("等待播放器授权") }
        }
        if player.isBrowser { return try AppleScriptAdapter.browserPlayback(player.id) }
        if player.kind == .quickTime { return try AppleScriptAdapter.quickTimePlayback() }
        if player.kind == .vlc {
            let state = try LocalHTTP().get(port: port, password: PasswordStore.read())
            guard ["playing", "paused"].contains(state["state"] as? String ?? ""),
                  let rate = state["rate"] as? Double, rate.isFinite, rate > 0 else { throw SlowFastError("等待视频") }
            return PlaybackSnapshot(rate: rate, isPlaying: state["state"] as? String == "playing")
        }
        let ipc = try MPVConnection(path: socket)
        guard try ipc.command(["get_property", "idle-active"]) as? Bool == false,
              let rate = try ipc.command(["get_property", "speed"]) as? Double, rate.isFinite, rate > 0,
              let paused = try ipc.command(["get_property", "pause"]) as? Bool else { throw SlowFastError("等待视频") }
        return PlaybackSnapshot(rate: rate, isPlaying: !paused)
    }

    static func run(_ player: PlayerChoice, socket: String, port: Int, askPermission: Bool) -> BrowserConnection {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.id) != nil else { return .notInstalled }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: player.id).contains(where: { !$0.isTerminated }) else { return .notRunning }
        if player.isBrowser { return BrowserSetup.probe(player.id, askPermission: askPermission) }
        do {
            switch player.kind {
            case .quickTime:
                let target = NSAppleEventDescriptor(bundleIdentifier: player.id)
                let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, askPermission)
                guard permission == noErr else { return .automation }
                let reply = try AppleScriptAdapter.run("tell application id \(AppleScriptAdapter.quote(player.id)) to return count of documents")
                return reply.int32Value > 0 ? .ready : .noMedia
            case .vlc:
                guard !PasswordStore.read().isEmpty else { return .localSetup }
                let state = try LocalHTTP().get(port: port, password: PasswordStore.read())
                return ["playing", "paused"].contains(state["state"] as? String ?? "") ? .ready : .noMedia
            case .iina, .mpv:
                guard FileManager.default.fileExists(atPath: NSString(string: socket).expandingTildeInPath) else { return .localSetup }
                let connection = try MPVConnection(path: socket)
                let idle = try connection.command(["get_property", "idle-active"]) as? Bool ?? true
                return idle ? .noMedia : .ready
            case .browser: return .unchecked
            }
        } catch { return .failed(error.localizedDescription) }
    }
}

enum LocalSetup {
    static func socketPath(for player: PlayerChoice) -> String {
        NSHomeDirectory() + "/Library/Application Support/SlowFast/" + (player.kind == .mpv ? "mpv.sock" : "iina.sock")
    }
    private static func write(_ text: String, to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("slowfast-\(Int(Date().timeIntervalSince1970)).backup")
            try manager.copyItem(at: url, to: backup)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // Called only after explicit user confirmation and a clean player shutdown.
    static func configure(_ player: PlayerChoice, port: Int) throws -> String? {
        let directory = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/SlowFast")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        switch player.kind {
        case .iina:
            let domain = player.id as CFString
            let old = CFPreferencesCopyAppValue("userOptions" as CFString, domain)
            guard old == nil || old is [[String]] else { throw SlowFastError("IINA 配置格式不同，请在其高级设置中手动添加 input-ipc-server") }
            var options = old as? [[String]] ?? []
            let enabled = CFPreferencesCopyAppValue("enableAdvancedSettings" as CFString, domain) as? Bool ?? false
            if let row = options.last(where: { $0.first == "input-ipc-server" }), row.count == 2 {
                guard enabled else { throw SlowFastError("IINA 已有接口设置，但高级设置尚未启用。请在 IINA 中开启高级设置后重试") }
                let path = NSString(string: row[1]).expandingTildeInPath
                guard path.hasPrefix("/"), path.utf8.count < 104 else { throw SlowFastError("IINA 已有的接口路径无效，请检查高级设置") }
                return path
            }
            guard enabled || options.isEmpty else { throw SlowFastError("IINA 有尚未启用的高级选项，请先在 IINA 中确认这些选项，再重试连接") }
            let path = socketPath(for: player)
            let backup: [String: Any] = ["userOptions": options, "enableAdvancedSettings": enabled]
            let data = try PropertyListSerialization.data(fromPropertyList: backup, format: .xml, options: 0)
            try data.write(to: directory.appendingPathComponent("IINA-before-setup.plist"), options: .atomic)
            options.append(["input-ipc-server", path])
            CFPreferencesSetAppValue("userOptions" as CFString, options as CFArray, domain)
            CFPreferencesSetAppValue("enableAdvancedSettings" as CFString, true as CFBoolean, domain)
            guard CFPreferencesAppSynchronize(domain) else { throw SlowFastError("IINA 设置无法保存") }
            return path
        case .mpv:
            let url = URL(fileURLWithPath: NSHomeDirectory() + "/.config/mpv/mpv.conf")
            let old = FileManager.default.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : ""
            if let path = ConfigEditing.value("input-ipc-server", in: old, globalOnly: true) {
                let expanded = NSString(string: path.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))).expandingTildeInPath
                guard expanded.hasPrefix("/"), expanded.utf8.count < 104 else { throw SlowFastError("mpv 已有的接口路径无法使用，请检查 mpv.conf") }
                return expanded
            }
            let path = socketPath(for: player)
            try write(ConfigEditing.setting(["input-ipc-server": path], in: old, beforeProfiles: true), to: url)
            return path
        case .vlc:
            guard (1024...65535).contains(port) else { throw SlowFastError("VLC 端口应为 1024–65535") }
            let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Preferences/org.videolan.vlc/vlcrc")
            let old = FileManager.default.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : ""
            let password = ConfigEditing.value("http-password", in: old).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
            var interfaces = (ConfigEditing.value("extraintf", in: old) ?? "").split(separator: ":").map(String.init)
            if !interfaces.contains("http") { interfaces.append("http") }
            let updated = try ConfigEditing.setting(["extraintf": interfaces.joined(separator: ":"), "http-host": "127.0.0.1", "http-port": String(port), "http-password": password], in: old)
            try PasswordStore.save(password)
            try write(updated, to: url)
            return nil
        default: return nil
        }
    }
}
