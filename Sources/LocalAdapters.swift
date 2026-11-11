// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import Security
import Darwin

enum PasswordStore {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.yeonza.SlowFast", kSecAttrAccount as String: "vlc-local-api"]
    static func read() -> String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ password: String) throws {
        if password.isEmpty { SecItemDelete(query as CFDictionary); return }
        let attributes = [kSecValueData as String: Data(password.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SlowFastError("无法将 VLC 密码保存到钥匙串（\(status)）") }
    }
}

final class LocalHTTP: NSObject, URLSessionTaskDelegate {
    // Never forward localhost credentials to a redirected address.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func get(port: Int, password: String, rate: Double? = nil) throws -> [String: Any] {
        guard (1024...65535).contains(port), !password.isEmpty else { throw SlowFastError("请先在 SlowFast 设置中填写 VLC 本地接口密码和端口") }
        var components = URLComponents(string: "http://127.0.0.1:\(port)/requests/status.json")!
        if let rate { components.queryItems = [URLQueryItem(name: "command", value: "rate"), URLQueryItem(name: "val", value: String(rate))] }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.setValue("Basic " + Data(":\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?; var status = 0; var failure: Error?
        let task = session.dataTask(with: request) { data, response, error in
            responseData = data; status = (response as? HTTPURLResponse)?.statusCode ?? 0; failure = error
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 3) == .success else { task.cancel(); throw SlowFastError("VLC 本地接口连接超时") }
        if status == 401 { throw SlowFastError("VLC 密码不正确，请在设置中重新填写") }
        guard failure == nil, status == 200, let data = responseData,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SlowFastError("无法连接 VLC；请按设置说明启用本地 HTTP 接口并重启 VLC")
        }
        return result
    }
    func control(port: Int, password: String, action: SpeedAction, requested: Double?) throws -> ControlResult {
        let state = try get(port: port, password: password)
        guard let current = state["rate"] as? Double, ["playing", "paused"].contains(state["state"] as? String ?? "") else {
            throw SlowFastError("VLC 尚未打开正在播放或暂停的视频")
        }
        let rate = SpeedScale.next(current, action: action, requested: requested)
        let updated = try get(port: port, password: password, rate: rate)
        guard let actual = updated["rate"] as? Double, abs(actual - rate) < 0.02 else { throw SlowFastError("VLC 未确认倍速变更") }
        return ControlResult(rate: actual, message: "VLC media player", isPlaying: updated["state"] as? String == "playing")
    }
}

final class MPVConnection {
    private let fd: Int32
    private var buffer = Data()
    private var sequence = 0
    init(path: String) throws {
        let expanded = NSString(string: path).expandingTildeInPath
        var address = sockaddr_un()
        let bytes = Array(expanded.utf8) + [0]
        guard expanded.hasPrefix("/"), bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw SlowFastError("IINA / mpv socket 路径无效或过长") }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SlowFastError("无法创建本地播放器连接") }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
        let result = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if result != 0 {
            let connectionError = errno
            guard connectionError == EINPROGRESS else {
                throw SlowFastError("无法连接 IINA / mpv；请按设置说明启用 input-ipc-server 并重启播放器")
            }
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            var socketError: Int32 = 0; var length = socklen_t(MemoryLayout<Int32>.size)
            let ready = poll(&descriptor, 1, 1500)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length)
            guard ready > 0, socketError == 0 else { throw SlowFastError("IINA / mpv 连接超时") }
        }
    }
    deinit { close(fd) }

    func command(_ args: [Any]) throws -> Any {
        sequence += 1
        var payload = try JSONSerialization.data(withJSONObject: ["command": args, "request_id": sequence])
        payload.append(10)
        let deadline = Date().addingTimeInterval(2)
        var offset = 0
        while offset < payload.count {
            try wait(for: POLLOUT, until: deadline)
            let written = payload.withUnsafeBytes { bytes in Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), payload.count - offset) }
            if written < 0, errno == EAGAIN || errno == EINTR { continue }
            guard written > 0 else { throw SlowFastError("播放器连接已关闭") }
            offset += written
        }
        while Date() < deadline {
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["request_id"] as? Int == sequence else { continue }
                guard object["error"] as? String == "success" else { throw SlowFastError("IINA / mpv 拒绝了倍速指令") }
                return object["data"] ?? NSNull()
            }
            try wait(for: POLLIN, until: deadline)
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count < 0, errno == EAGAIN || errno == EINTR { continue }
            guard count > 0 else { throw SlowFastError("播放器连接已关闭") }
            buffer.append(contentsOf: chunk.prefix(count))
            guard buffer.count <= 65536 else { throw SlowFastError("播放器响应过大") }
        }
        throw SlowFastError("IINA / mpv 响应超时")
    }

    private func wait(for event: Int32, until deadline: Date) throws {
        let remaining = Int32(max(0, deadline.timeIntervalSinceNow * 1000))
        var descriptor = pollfd(fd: fd, events: Int16(event), revents: 0)
        guard remaining > 0, poll(&descriptor, 1, remaining) > 0,
              descriptor.revents & Int16(event) != 0 else { throw SlowFastError("播放器连接超时或已关闭") }
    }

    func control(action: SpeedAction, requested: Double?) throws -> ControlResult {
        guard let idle = try command(["get_property", "idle-active"]) as? Bool, !idle,
              let current = try command(["get_property", "speed"]) as? Double else { throw SlowFastError("IINA / mpv 尚未打开视频") }
        let rate = SpeedScale.next(current, action: action, requested: requested)
        _ = try command(["set_property", "speed", rate])
        guard let actual = try command(["get_property", "speed"]) as? Double, abs(actual - rate) < 0.01 else {
            throw SlowFastError("IINA / mpv 未确认倍速变更")
        }
        return ControlResult(rate: actual, message: "IINA / mpv")
    }
}
