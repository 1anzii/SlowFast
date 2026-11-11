// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit

enum AppleScriptAdapter {
    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // Run on the controller's serial worker, never in the keyboard event callback.
    static func run(_ source: String, timeoutSeconds: Int = 5) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: "with timeout of \(timeoutSeconds) seconds\n" + source + "\nend timeout") else {
            throw SlowFastError("无法创建播放器控制指令")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            let detail = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
            throw AppleScriptFailure(number: number, detail: detail)
        }
        return result
    }

    static func browser(_ id: String, action: SpeedAction, requested: Double?) throws -> ControlResult {
        guard let url = Bundle.main.url(forResource: "video", withExtension: "js") else { throw SlowFastError("缺少网页控制组件") }
        let code = try String(contentsOf: url, encoding: .utf8)
        var request: [String: Any] = ["kind": "change", "action": action.rawValue]
        if let requested { request["rate"] = requested }
        let json = String(data: try JSONSerialization.data(withJSONObject: request), encoding: .utf8)!
        let expression = "(function(){" + code + "\nreturn JSON.stringify(slowfastControl(" + json + "));})()"
        let command: String
        if SupportedApp.safari.contains(id) {
            command = "do JavaScript \(quote(expression)) in current tab of front window"
        } else {
            command = "execute active tab of front window javascript \(quote(expression))"
        }
        let output = try run("""
        tell application id \(quote(id))
            if (count of windows) is 0 then error "请先打开一个视频标签页"
            return \(command)
        end tell
        """)
        guard let string = output.stringValue, let data = string.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SlowFastError("浏览器没有返回倍速状态；请确认允许来自 Apple 事件的 JavaScript")
        }
        guard result["ok"] as? Bool == true, let rate = result["rate"] as? Double else {
            throw SlowFastError(result["message"] as? String ?? "当前页面无法控制")
        }
        return ControlResult(rate: rate, message: "当前网页视频", isPlaying: result["playing"] as? Bool)
    }

    static func browserPlayback(_ id: String) throws -> PlaybackSnapshot {
        guard let url = Bundle.main.url(forResource: "video", withExtension: "js") else { throw SlowFastError("缺少网页控制组件") }
        let code = try String(contentsOf: url, encoding: .utf8)
        let expression = "(function(){" + code + "\nreturn JSON.stringify(slowfastControl({kind:'status'}));})()"
        let command = SupportedApp.safari.contains(id)
            ? "do JavaScript \(quote(expression)) in current tab of front window"
            : "execute active tab of front window javascript \(quote(expression))"
        let output = try run("""
        tell application id \(quote(id))
            if (count of windows) is 0 then error "SLOWFAST_NO_PAGE"
            return \(command)
        end tell
        """, timeoutSeconds: 2)
        guard let text = output.stringValue, let data = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["ok"] as? Bool == true,
              let rate = object["rate"] as? Double, rate.isFinite, rate > 0,
              let playing = object["playing"] as? Bool else { throw SlowFastError("等待可控制的视频") }
        return PlaybackSnapshot(rate: rate, isPlaying: playing)
    }

    static func quickTimePlayback() throws -> PlaybackSnapshot {
        let output = try run("""
        tell application id "com.apple.QuickTimePlayerX"
            if (count of documents) is 0 then error "SLOWFAST_NO_VIDEO"
            return {rate of front document, playing of front document}
        end tell
        """, timeoutSeconds: 2)
        let rate = output.atIndex(1)?.doubleValue ?? 0
        return PlaybackSnapshot(rate: rate.isFinite && rate > 0 ? rate : nil, isPlaying: output.atIndex(2)?.booleanValue == true)
    }

    static func quickTime(action: SpeedAction, requested: Double?) throws -> ControlResult {
        let calculation: String
        switch action {
        case .reset: calculation = "set targetRate to 1"
        case .set: calculation = "set targetRate to \(SpeedScale.next(1, action: .set, requested: requested))"
        case .faster:
            calculation = """
            set targetRate to 2
            repeat with candidate in {0.5, 0.75, 1, 1.25, 1.5, 2}
                if (candidate as real) > oldRate + 0.001 then
                    set targetRate to candidate as real
                    exit repeat
                end if
            end repeat
            """
        case .slower:
            calculation = """
            set targetRate to 0.5
            repeat with candidate in {2, 1.5, 1.25, 1, 0.75, 0.5}
                if (candidate as real) < oldRate - 0.001 then
                    set targetRate to candidate as real
                    exit repeat
                end if
            end repeat
            """
        }
        let result = try run("""
        tell application id "com.apple.QuickTimePlayerX"
            if (count of documents) is 0 then error "QuickTime 尚未打开视频"
            set movie to front document
            if not (playing of movie) then error "请先播放 QuickTime 视频，再调节倍速"
            set oldRate to rate of movie
            \(calculation)
            set rate of movie to targetRate
            set actualRate to rate of movie
            if actualRate < targetRate - 0.01 or actualRate > targetRate + 0.01 then error "QuickTime 拒绝了此视频的倍速设置"
            return actualRate
        end tell
        """)
        return ControlResult(rate: result.doubleValue, message: "QuickTime Player", isPlaying: true)
    }
}
