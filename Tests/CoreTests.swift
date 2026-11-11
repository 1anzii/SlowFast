// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import CoreGraphics
import Darwin

@main struct Tests {
    static func main() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
        }
        check(SpeedScale.next(1, action: .slower) == 0.75, "1 → 0.75")
        check(SpeedScale.next(1, action: .faster) == 1.25, "1 → 1.25")
        check(SpeedScale.next(1.7, action: .slower) == 1.5, "off-grid slow")
        check(SpeedScale.next(1.7, action: .faster) == 2, "off-grid fast")
        check(SpeedScale.next(0.5, action: .slower) == 0.5, "lower boundary")
        check(SpeedScale.next(2, action: .faster) == 2, "upper boundary")
        check(SpeedScale.next(2, action: .reset) == 1, "reset")
        check(SpeedScale.next(.nan, action: .faster) == 1.25, "invalid current")
        check(SpeedScale.next(1, action: .set, requested: 42) == 1, "reject invalid rate")
        check(HotKey.action(keyCode: 43, flags: .maskSecondaryFn) == .slower, "Fn comma")
        check(HotKey.action(keyCode: 47, flags: .maskSecondaryFn) == .faster, "Fn period")
        check(HotKey.action(keyCode: 44, flags: [.maskSecondaryFn, .maskShift]) == .reset, "Fn question")
        check(HotKey.action(keyCode: 44, flags: .maskSecondaryFn) == .reset, "Fn slash")
        check(HotKey.action(keyCode: 43, flags: []) == nil, "plain comma must pass")
        check(HotKey.action(keyCode: 47, flags: [.maskSecondaryFn, .maskCommand]) == nil, "other modifiers must pass")
        check(HotKey.action(keyCode: 43, flags: [.maskSecondaryFn, .maskShift]) == nil, "angle brackets must pass")
        check(HotKey.action(keyCode: 0, flags: .maskSecondaryFn) == nil, "unrelated Fn key must pass")
        print("PASS: speed boundaries, off-grid transitions, reset, physical Fn key matching")
        var tape = TapeMotion()
        tape.update(rate: 1, playing: true, at: 100)
        let first = tape.angle(at: 101)
        tape.update(rate: 2, playing: true, at: 101)
        check(tape.angle(at: 101) == first, "speed changes must preserve reel position")
        check(abs((tape.angle(at: 102) - first) / first - 2) < 0.001, "2x must rotate twice as fast")
        tape.update(rate: 0.5, playing: true, at: 102)
        check(abs(tape.angle(at: 103) - tape.angle(at: 102) - first * 0.5) < 0.001, "0.5x must rotate at half speed")
        tape.update(rate: 0.5, playing: false, at: 103)
        check(tape.angle(at: 110) == tape.angle(at: 103), "paused video freezes the reels")
        tape.update(rate: nil, playing: true, at: 110)
        check(tape.angle(at: 115) == tape.angle(at: 110), "unknown speed never fabricates motion")
        tape.update(rate: .nan, playing: true, at: 115)
        check(tape.angle(at: 120).isFinite, "invalid rate must not poison animation")
        print("PASS: reel phase continuity, proportional speed, pause, unknown and invalid rates")
        check(BrowserConnection.classify(number: 8, detail: "You must enable 'Allow JavaScript from Apple Events' to use 'do JavaScript'.") == .javascript, "Safari setup error")
        check(BrowserConnection.classify(number: 12, detail: "通过 AppleScript 执行 JavaScript 的功能已关闭。") == .javascript, "Chrome setup error")
        check(BrowserConnection.classify(number: -1744, detail: "") == .automation, "silent preflight needs consent")
        check(BrowserConnection.classify(number: -2700, detail: "SLOWFAST_NO_PAGE") == .noPage, "no page is not a permission error")
        check(BrowserConnection.classify(number: 12, detail: "JavaScript SyntaxError: Unexpected token") == .failed("JavaScript SyntaxError: Unexpected token"), "runtime errors must not become setup errors")
        print("PASS: browser setup classification, consent, no-page and JavaScript runtime errors")
        check(!BrowserConnection.notRunning.needsSetup, "stopped player is not broken")
        check(BrowserConnection.noMedia.connected, "empty player can still be connected")
        check(!BrowserConnection.extensionManual.connected, "extension forwarding is not verified connection")
        check(Set(PlayerChoice.all.map(\.id)).count == PlayerChoice.all.count, "unique player IDs")
        check(PlayerChoice.all.allSatisfy { SupportedApp.supports($0.id) }, "catalog matches adapters")
        let existing = "# comment\nvolume=77\nextraintf=old\n#http-host=0.0.0.0\nhttp-host=0.0.0.0\n"
        let edited = try ConfigEditing.setting(["extraintf": "old:http", "http-host": "127.0.0.1"], in: existing)
        check(edited.contains("volume=77"), "retain unrelated preferences")
        check(edited.contains("#http-host=0.0.0.0"), "retain comments")
        check(ConfigEditing.value("http-host", in: edited) == "127.0.0.1", "force loopback for VLC")
        check(ConfigEditing.value("extraintf", in: edited) == "old:http", "retain other interfaces")
        let mpv = try ConfigEditing.setting(["input-ipc-server": "/tmp/local.sock"], in: "volume=42\n[profile]\nscale=spline36\n", beforeProfiles: true)
        check(mpv.range(of: "input-ipc-server")!.lowerBound < mpv.range(of: "[profile]")!.lowerBound, "IPC belongs to global config, not a profile")
        let profileOnly = "volume=42\n[cinema]\ninput-ipc-server=/tmp/cinema.sock\nscale=spline36\n"
        check(ConfigEditing.value("input-ipc-server", in: profileOnly, globalOnly: true) == nil, "named profile must not be mistaken for an active global IPC setting")
        let scoped = try ConfigEditing.setting(["input-ipc-server": "/tmp/global.sock"], in: profileOnly, beforeProfiles: true)
        check(scoped.contains("[cinema]\ninput-ipc-server=/tmp/cinema.sock\nscale=spline36"), "repair must preserve named profile settings verbatim")
        check(ConfigEditing.value("input-ipc-server", in: scoped, globalOnly: true) == "/tmp/global.sock", "global socket inserted independently")
        let resumed = scoped + "[default] # resume global options\ninput-ipc-server=/tmp/resumed.sock\n[other]\ninput-ipc-server=/tmp/other.sock\n"
        check(ConfigEditing.value("input-ipc-server", in: resumed, globalOnly: true) == "/tmp/resumed.sock", "default profile resumes global options; last global value wins")
        let replaced = try ConfigEditing.setting(["input-ipc-server": "/tmp/new.sock"], in: resumed, beforeProfiles: true)
        check(ConfigEditing.value("input-ipc-server", in: replaced, globalOnly: true) == "/tmp/new.sock", "replaced global value must not be overridden by old default section")
        check(replaced.contains("input-ipc-server=/tmp/cinema.sock") && replaced.contains("input-ipc-server=/tmp/other.sock"), "both named profiles retained")
        print("PASS: mpv named profiles preserved; default section and global IPC selection")
        do { _ = try ConfigEditing.setting(["key": "value\nunsafe=yes"], in: ""); fatalError("newline must be rejected") } catch is SlowFastError {}
        print("PASS: truthful connection states, player catalog, safe local configuration merge")

        let args = CommandLine.arguments
        if args.count > 2, args[1] == "ipc" {
            let connection = try MPVConnection(path: args[2])
            let result = try connection.control(action: .faster, requested: nil)
            check(result.rate == 1.25, "IPC must report verified rate")
            let reset = try connection.control(action: .reset, requested: nil)
            check(reset.rate == 1, "IPC reset")
            print("PASS: fragmented IPC, unrelated events, request IDs, speed readback")
        }
        if args.count > 2, args[1] == "http" {
            let port = Int(args[2])!
            let result = try LocalHTTP().control(port: port, password: "slowfast-test", action: .slower, requested: nil)
            check(result.rate == 0.75, "HTTP verified rate")
            do {
                _ = try LocalHTTP().control(port: port, password: "wrong", action: .faster, requested: nil)
                fatalError("must reject wrong credentials")
            } catch let error as SlowFastError { check(error.message.contains("密码"), "authentication error") }
            print("PASS: authenticated VLC request, paused state, readback, wrong-password error")
        }
        if args.count > 2, args[1] == "ipc-refused" {
            let descriptorCount = { (0..<1024).filter { fcntl(Int32($0), F_GETFD) >= 0 }.count }
            let before = descriptorCount()
            do {
                _ = try MPVConnection(path: args[2]).control(action: .faster, requested: nil)
                fatalError("must reject missing socket")
            } catch is SlowFastError { print("PASS: absent IPC socket produces useful error") }
            for _ in 0..<200 { _ = try? MPVConnection(path: args[2]) }
            check(descriptorCount() == before, "repeated failed checks must not leak file descriptors")
            print("PASS: repeated failed IPC connection checks release descriptors")
        }
    }
}
