// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import ApplicationServices
import CoreServices

struct BrowserChoice: Identifiable {
    let id: String
    let name: String
}

enum BrowserSetup {
    static let supported = [
        ("com.google.Chrome", "Chrome"), ("com.apple.Safari", "Safari"),
        ("com.microsoft.edgemac", "Edge"), ("com.brave.Browser", "Brave"),
        ("com.vivaldi.Vivaldi", "Vivaldi"), ("company.thebrowser.Browser", "Arc"),
        ("com.google.Chrome.beta", "Chrome Beta"), ("com.google.Chrome.canary", "Chrome Canary"),
        ("com.apple.SafariTechnologyPreview", "Safari Technology Preview")
    ]

    // Runs on the serial player worker. A silent check never raises a permission prompt.
    static func probe(_ id: String, askPermission: Bool) -> BrowserConnection {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { !$0.isTerminated }) else { return .notRunning }
        let target = NSAppleEventDescriptor(bundleIdentifier: id)
        let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, askPermission)
        if permission != noErr { return .classify(number: Int(permission), detail: "系统尚未允许自动化控制") }
        let expression = AppleScriptAdapter.quote("'SlowFast connection OK'")
        let command = SupportedApp.safari.contains(id)
            ? "do JavaScript \(expression) in current tab of front window"
            : "execute active tab of front window javascript \(expression)"
        do {
            let result = try AppleScriptAdapter.run("""
            tell application id \(AppleScriptAdapter.quote(id))
                if (count of windows) is 0 then error "SLOWFAST_NO_PAGE"
                return \(command)
            end tell
            """)
            return result.stringValue == "SlowFast connection OK" ? .ready : .failed("浏览器没有返回连接确认")
        } catch let error as AppleScriptFailure {
            return .classify(number: error.number, detail: error.detail)
        } catch { return .failed(error.localizedDescription) }
    }

    @MainActor static func launch(_ id: String) async throws -> NSRunningApplication {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            running.activate(options: []); return running
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { throw SlowFastError("未找到此浏览器") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    @MainActor static func openVerificationPage(_ id: String) async throws {
        guard let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
              let page = Bundle.main.url(forResource: "ConnectionTest", withExtension: "html") else {
            throw SlowFastError("缺少连接检测页面，请重新安装 SlowFast")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open([page], withApplicationAt: browser, configuration: configuration)
    }

    // Use the browser's visible settings UI. Do not write browser preferences or TCC databases.
    // Safari's security confirmation is intentionally left for the user.
    @MainActor static func enableJavaScript(_ id: String) async throws -> BrowserConnection {
        guard AXIsProcessTrusted() else { throw SlowFastError("请先开启 SlowFast 的辅助功能权限") }
        let running = try await launch(id)
        for _ in 0..<20 {
            if running.isActive { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let root = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.8)
        if SupportedApp.safari.contains(id) {
            let menu = try await waitFor { elementAttribute(root, kAXMenuBarAttribute) }
            let settings = try await waitFor {
                find(menu, role: kAXMenuItemRole, names: ["设置…", "设置...", "Settings…", "Settings...", "偏好设置…", "Preferences…"])
            }
            try press(settings)
            let advanced = try await waitFor { find(root, role: kAXButtonRole, names: ["高级", "Advanced"]) }
            try press(advanced)
            let features = try await waitFor {
                find(root, role: kAXCheckBoxRole, names: ["显示网页开发者功能", "Show features for web developers", "在菜单栏中显示开发菜单", "Show Develop menu in menu bar"])
            }
            if !isChecked(features) { try press(features) }
            let developer = try await waitFor { find(root, role: kAXButtonRole, names: ["开发者", "Developer"]) }
            try press(developer)
            let toggle = try await waitFor {
                find(root, role: kAXCheckBoxRole, names: ["允许Apple事件中的JavaScript", "Allow JavaScript from Apple Events"])
            }
            if isChecked(toggle) { return .ready }
            try press(toggle)
            // Wait only for observable confirmation; never accept the security alert.
            return .confirmation
        }
        let menu = try await waitFor { elementAttribute(root, kAXMenuBarAttribute) }
        let view = try await waitFor { find(menu, role: kAXMenuBarItemRole, names: ["显示", "查看", "View"]) }
        try press(view)
        if let developer = find(menu, role: kAXMenuItemRole, names: ["开发者", "Developer"]) { try? press(developer) }
        let toggle = try await waitFor {
            find(menu, role: kAXMenuItemRole, names: ["允许Apple事件中的JavaScript", "允许来自Apple事件的JavaScript", "Allow JavaScript from Apple Events"])
        }
        if let mark = attribute(toggle, "AXMenuItemMarkChar") as? String, !mark.isEmpty { return .ready }
        try press(toggle)
        return .checking // The caller must verify with a fresh JavaScript probe.
    }

    private static func normalized(_ text: String) -> String { text.lowercased().filter { !$0.isWhitespace } }
    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    private static func elementAttribute(_ element: AXUIElement, _ key: String) -> AXUIElement? {
        guard let value = attribute(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func isChecked(_ element: AXUIElement) -> Bool { (attribute(element, kAXValueAttribute) as? NSNumber)?.boolValue == true }
    private static func find(_ root: AXUIElement, role: String, names: [String]) -> AXUIElement? {
        let names = Set(names.map(normalized))
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count && index < 1200 {
            let (item, depth) = queue[index]; index += 1
            let itemRole = attribute(item, kAXRoleAttribute) as? String ?? ""
            if itemRole == role {
                let title = attribute(item, kAXTitleAttribute) as? String ?? ""
                let description = attribute(item, kAXDescriptionAttribute) as? String ?? ""
                if names.contains(normalized(title)) || names.contains(normalized(description)) { return item }
            }
            // Browser page contents are irrelevant to configuring the browser itself.
            guard depth < 10, itemRole != "AXWebArea", itemRole != "AXHTMLContent" else { continue }
            let children = attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? []
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return nil
    }
    private static func press(_ element: AXUIElement) throws {
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw SlowFastError("浏览器未接受自动操作，请按下方步骤手动开启")
        }
    }
    @MainActor private static func waitFor(_ lookup: () -> AXUIElement?) async throws -> AXUIElement {
        for _ in 0..<20 {
            if let element = lookup() { return element }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw SlowFastError("没有找到对应设置。浏览器版本或界面语言可能不同，请手动开启该选项")
    }
}
