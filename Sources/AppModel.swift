// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import SwiftUI
import ApplicationServices

final class AppModel: ObservableObject {
    @Published var enabled = true { didSet { listener.enabled = enabled; onMenuChange?() } }
    @Published var accessibilityReady = AXIsProcessTrusted()
    @Published var hotKeysReady = false
    @Published var rate: Double?
    @Published var playbackPlaying = false
    @Published var playbackKnown = false
    @Published var status = "打开视频，按下 Fn + . 试试看"
    @Published var lastError = false
    @Published var busy = false
    @Published var recentResults: [String] = []
    @Published var targetName = "等待播放器"
    @Published var targetSupported = false
    @Published var targetIsChromium = false
    @Published var targetBundleID = ""
    @Published var browserConnections: [String: BrowserConnection] = [:]
    @Published var availableBrowsers: [BrowserChoice] = []
    @Published var setupBrowserID: String?
    @Published var installedIDs = Set<String>()
    @Published var connectionDetail = ""
    @Published var selfCheckSummary = ""
    @Published var checkingAll = false
    @Published var showAdvanced = false {
        didSet { if showAdvanced != oldValue { onAdvancedChange?(showAdvanced) } }
    }
    @Published var showHistory = false
    var installedPlayers: [PlayerChoice] { PlayerChoice.all.filter { installedIDs.contains($0.id) } }
    var otherPlayers: [PlayerChoice] { PlayerChoice.all.filter { !installedIDs.contains($0.id) && !$0.name.contains("Beta") && !$0.name.contains("Canary") && !$0.name.contains("Preview") } }
    func connection(_ id: String) -> BrowserConnection { browserConnections[id] ?? (installedIDs.contains(id) ? .unchecked : .notInstalled) }
    func socket(for id: String) -> String {
        if id == "io.mpv" { return UserDefaults.standard.string(forKey: "mpvSocketPath") ?? LocalSetup.socketPath(for: PlayerChoice.all.first { $0.id == id }!) }
        return socketPath
    }
    var currentConnection: BrowserConnection? { browserConnections[targetBundleID] }
    var canControlFromWindow: Bool {
        enabled && !busy && setupBrowserID == nil && targetSupported && !(extensionMode && targetIsChromium)
    }
    @Published var extensionMode = UserDefaults.standard.bool(forKey: "extensionMode") {
        didSet {
            UserDefaults.standard.set(extensionMode, forKey: "extensionMode")
            for id in SupportedApp.chromium { browserConnections[id] = .unchecked }
            DispatchQueue.main.async { self.checkAllConnections() }
        }
    }
    @Published var socketPath = UserDefaults.standard.string(forKey: "socketPath") ?? "~/Library/Application Support/SlowFast/iina.sock" {
        didSet { UserDefaults.standard.set(socketPath, forKey: "socketPath") }
    }
    @Published var vlcPort = UserDefaults.standard.string(forKey: "vlcPort") ?? "8080" {
        didSet { UserDefaults.standard.set(vlcPort, forKey: "vlcPort") }
    }
    @Published var vlcPassword = ""
    @Published var passwordStatus = ""
    var onMenuChange: (() -> Void)?
    var onFeedback: ((String, String, Bool) -> Void)?
    var onHidePanel: (() -> Void)?
    var onShowPanel: (() -> Void)?
    var onAdvancedChange: ((Bool) -> Void)?
    private let listener = HotKeyListener()
    private let worker = DispatchQueue(label: "com.yeonza.SlowFast.player")
    private var lastExternalApp: NSRunningApplication?
    private var observer: NSObjectProtocol?
    private var pollTimer: Timer?
    private var playbackTimer: Timer?
    private var panelVisible = false
    private var readingPlayback = false
    private var playbackGeneration = 0
    private var pendingCount = 0
    private var checkingBrowsers = Set<String>()
    private var checkWaiters: [String: [(BrowserConnection) -> Void]] = [:]
    private var lastBrowserChecks: [String: Date] = [:]
    private var waitingForBrowser: (id: String, until: Date)?
    private var resumeRepairID: String?
    private var waitingForShortcutPermission = false

    func start() {
        refreshInstalled()
        availableBrowsers = BrowserSetup.supported.compactMap { id, name in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) == nil ? nil : BrowserChoice(id: id, name: name)
        }
        lastExternalApp = NSWorkspace.shared.frontmostApplication
        if lastExternalApp?.bundleIdentifier == Bundle.main.bundleIdentifier { lastExternalApp = nil }
        refreshTarget()
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            if self?.lastExternalApp?.processIdentifier != app.processIdentifier {
                self?.rate = nil
                self?.invalidatePlayback()
                self?.lastError = false
            }
            self?.lastExternalApp = app
            self?.refreshTarget()
        }
        listener.onAction = { [weak self] action in self?.perform(action, origin: "Fn") }
        refreshPermissions()
        checkAllConnections()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshPermissions()
            if let waiting = self.waitingForBrowser {
                if Date() < waiting.until { self.checkBrowser(waiting.id, force: true) }
                else { self.waitingForBrowser = nil }
            }
        }
    }

    func stop() {
        listener.stop(); pollTimer?.invalidate(); playbackTimer?.invalidate()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func refreshTarget() {
        let id = lastExternalApp?.bundleIdentifier ?? ""
        targetBundleID = id
        targetSupported = SupportedApp.supports(id)
        targetIsChromium = SupportedApp.chromium.contains(id)
        targetName = targetSupported ? (lastExternalApp?.localizedName ?? "播放器") : "等待视频"
        if setupBrowserID == nil, SupportedApp.supports(id) {
            checkBrowser(id)
        }
        onMenuChange?()
    }

    func capturePanelTarget() {
        if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            if lastExternalApp?.processIdentifier != app.processIdentifier { rate = nil; lastError = false; invalidatePlayback() }
            lastExternalApp = app
        }
        refreshTarget()
    }

    private func invalidatePlayback() {
        playbackGeneration += 1; playbackKnown = false; playbackPlaying = false
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        playbackTimer?.invalidate(); playbackTimer = nil
        invalidatePlayback()
        guard visible else { return }
        refreshPlayback()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshPlayback() }
    }

    // Read only while the cassette is visible. Never ask for new permissions here.
    private func refreshPlayback() {
        guard panelVisible, !readingPlayback, !busy, setupBrowserID == nil,
              !(extensionMode && targetIsChromium),
              let app = lastExternalApp, !app.isTerminated,
              let player = PlayerChoice.all.first(where: { $0.id == targetBundleID }) else { return }
        readingPlayback = true
        let generation = playbackGeneration, pid = app.processIdentifier
        let socket = socket(for: player.id), port = Int(vlcPort) ?? 0
        worker.async { [weak self] in
            let result = try? ConnectionProbe.playback(player, socket: socket, port: port)
            DispatchQueue.main.async {
                guard let self else { return }
                self.readingPlayback = false
                guard self.panelVisible, self.playbackGeneration == generation,
                      self.lastExternalApp?.processIdentifier == pid, !self.busy else { return }
                self.playbackKnown = result != nil
                self.playbackPlaying = result?.isPlaying == true
                self.rate = result?.rate
                self.onMenuChange?()
            }
        }
    }

    func checkBrowser(_ id: String, force: Bool = false, askPermission: Bool = false,
                      completion: ((BrowserConnection) -> Void)? = nil) {
        guard let player = PlayerChoice.all.first(where: { $0.id == id }) else { return }
        if checkingBrowsers.contains(id) {
            if let completion { checkWaiters[id, default: []].append(completion) }
            return
        }
        if !force, let date = lastBrowserChecks[id], Date().timeIntervalSince(date) < 15 { return }
        if extensionMode && SupportedApp.chromium.contains(id) {
            browserConnections[id] = .extensionManual; completion?(.extensionManual); return
        }
        checkingBrowsers.insert(id)
        if waitingForBrowser?.id != id { browserConnections[id] = .checking }
        let socket = socket(for: id), port = Int(vlcPort) ?? 0
        worker.async { [weak self] in
            let result = ConnectionProbe.run(player, socket: socket, port: port, askPermission: askPermission)
            DispatchQueue.main.async {
                guard let self else { return }
                self.checkingBrowsers.remove(id)
                self.lastBrowserChecks[id] = Date()
                if self.waitingForBrowser?.id == id, result == .javascript {
                    self.browserConnections[id] = .confirmation
                } else { self.browserConnections[id] = result }
                if self.waitingForBrowser?.id == id, result.connected {
                    self.waitingForBrowser = nil
                    self.connectionDetail = "\(player.name) 已连接，回到视频即可调速"
                    self.onFeedback?("已连接", player.name, false)
                    self.onShowPanel?()
                }
                completion?(result)
                let waiters = self.checkWaiters.removeValue(forKey: id) ?? []
                waiters.forEach { $0(result) }
            }
        }
    }

    func configureBrowser(_ id: String) {
        guard setupBrowserID == nil, !checkingBrowsers.contains(id) else { return }
        guard let player = PlayerChoice.all.first(where: { $0.id == id }) else { return }
        if !player.isBrowser { repairLocalPlayer(player); return }
        if connection(id) == .confirmation {
            onHidePanel?()
            Task { @MainActor in _ = try? await BrowserSetup.launch(id) }
            waitingForBrowser = (id, Date().addingTimeInterval(120))
            return
        }
        if extensionMode && SupportedApp.chromium.contains(id) { showAdvanced = true; return }
        guard accessibilityReady else { resumeRepairID = id; repairShortcutPermission(); return }
        let name = player.name
        let consentKey = "repairConsent." + id
        if !UserDefaults.standard.bool(forKey: consentKey) {
        let alert = NSAlert()
        alert.messageText = "自动连接 \(name)？"
        alert.informativeText = "SlowFast 将打开浏览器设置并开启「允许 Apple 事件中的 JavaScript」。这会允许已获自动化授权的本机程序在网页中执行脚本。浏览器或系统弹出的安全确认，需要你亲自点「允许」。"
        alert.addButton(withTitle: "开始配置")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.set(true, forKey: consentKey)
        }
        setupBrowserID = id
        connectionDetail = "正在连接 \(name)…"
        onHidePanel?()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await BrowserSetup.launch(id)
                try await BrowserSetup.openVerificationPage(id)
                self.checkBrowser(id, force: true, askPermission: true) { [weak self] state in
                    guard let self else { return }
                    guard state == .javascript else {
                        self.setupBrowserID = nil
                        if state == .automation {
                            self.connectionDetail = "在系统自动化设置中打开 \(name)，完成后会自动复查"
                            self.waitingForBrowser = (id, Date().addingTimeInterval(120))
                            self.openAutomation()
                        } else {
                            self.connectionDetail = state.connected ? "\(name) 已连接，回到视频即可调速" : state.title
                            self.onShowPanel?()
                        }
                        self.onFeedback?(state == .ready ? "已连接" : "还差一步", state.title, state != .ready)
                        return
                    }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        do {
                            let result = try await BrowserSetup.enableJavaScript(id)
                            self.setupBrowserID = nil
                            if result == .confirmation {
                                self.browserConnections[id] = result
                                self.connectionDetail = "在 \(name) 的安全提示中点「允许」，随后自动验证"
                                self.waitingForBrowser = (id, Date().addingTimeInterval(120))
                            } else {
                                try await Task.sleep(nanoseconds: 300_000_000)
                                self.checkBrowser(id, force: true) { result in
                                    self.connectionDetail = result.connected ? "\(name) 已连接" : "\(name)：\(result.title)，展开该行查看步骤"
                                    self.onShowPanel?()
                                }
                            }
                        } catch {
                            self.setupBrowserID = nil
                            self.browserConnections[id] = .failed(error.localizedDescription)
                            self.connectionDetail = error.localizedDescription
                            self.onShowPanel?()
                            self.onFeedback?("需要手动完成", "请从菜单栏打开 SlowFast 查看步骤", true)
                        }
                    }
                }
            } catch {
                self.setupBrowserID = nil
                self.browserConnections[id] = .failed(error.localizedDescription)
                self.connectionDetail = error.localizedDescription
                self.onShowPanel?()
            }
        }
    }

    func refreshPermissions() {
        let wasReady = hotKeysReady
        accessibilityReady = AXIsProcessTrusted()
        if accessibilityReady { hotKeysReady = listener.start() }
        else { listener.stop(); hotKeysReady = false }
        onMenuChange?()
        if !wasReady && hotKeysReady {
            let completedPermissionRepair = waitingForShortcutPermission
            if waitingForShortcutPermission {
                waitingForShortcutPermission = false
                connectionDetail = "快捷键已就绪"
            }
            if let id = resumeRepairID {
                resumeRepairID = nil
                DispatchQueue.main.async { self.configureBrowser(id) }
            } else if completedPermissionRepair {
                DispatchQueue.main.async { self.checkAllConnections() }
            }
        }
    }

    func refreshInstalled() {
        installedIDs = Set(PlayerChoice.all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }.map(\.id))
    }

    func checkAllConnections() {
        guard !checkingAll, setupBrowserID == nil else { return }
        refreshInstalled(); refreshPermissions()
        checkingAll = true; selfCheckSummary = "正在检查…"
        var remaining = installedPlayers.count
        func finish() {
            self.checkingAll = false
            let issues = self.installedPlayers.filter { self.connection($0.id).needsSetup }.count + (self.hotKeysReady ? 0 : 1)
            let resourcesOK = ["video.js", "ConnectionTest.html", "connection-test.mp4"].allSatisfy { name in
                guard let url = Bundle.main.resourceURL?.appendingPathComponent(name),
                      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
                return size > 0
            }
            self.selfCheckSummary = !resourcesOK ? "自检发现组件缺失，请重新安装" : issues == 0 ? "自检完成 · \(self.installedPlayers.count) 个播放器" : "自检完成 · \(issues) 项需要连接"
        }
        if remaining == 0 { finish(); return }
        for player in installedPlayers {
            checkBrowser(player.id, force: true) { _ in remaining -= 1; if remaining == 0 { finish() } }
        }
    }

    func connectionAction(_ player: PlayerChoice) {
        let state = connection(player.id)
        if state == .notInstalled { if let url = URL(string: player.website) { NSWorkspace.shared.open(url) }; return }
        if state.connected || state == .unchecked { checkBrowser(player.id, force: true); return }
        if state == .extensionManual { showAdvanced = true; return }
        configureBrowser(player.id)
    }

    func repairShortcutPermission() {
        listener.stop(); refreshPermissions()
        if hotKeysReady { connectionDetail = "快捷键监听已恢复"; return }
        waitingForShortcutPermission = true
        connectionDetail = "请在辅助功能中开启 SlowFast；若已开启仍无效，移除旧条目，再添加「应用程序」里的 SlowFast"
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibility()
    }

    private func repairLocalPlayer(_ player: PlayerChoice) {
        if player.kind != .quickTime {
            let alert = NSAlert()
            alert.messageText = "自动连接 \(player.name)？"
            alert.informativeText = player.kind == .vlc
                ? "将备份 VLC 配置，启用仅限本机的 HTTP 接口并保存密码，然后重启 VLC。当前播放会暂停，完成后请重新打开视频。"
                : "将为 \(player.name) 配置本机控制接口并保留原设置备份，然后重启播放器。当前播放会暂停；IINA / mpv 请只打开一个播放窗口。"
            alert.addButton(withTitle: "配置并重启"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        setupBrowserID = player.id; connectionDetail = "正在连接 \(player.name)…"; onHidePanel?()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if player.kind != .quickTime {
                    let running = NSRunningApplication.runningApplications(withBundleIdentifier: player.id)
                    for app in running { guard app.terminate() else { throw SlowFastError("请先退出 \(player.name)，再点击修复") } }
                    for _ in 0..<50 {
                        if running.allSatisfy(\.isTerminated) { break }
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    guard running.allSatisfy(\.isTerminated) else { throw SlowFastError("\(player.name) 正等待退出确认，请完成后重试") }
                    if let path = try LocalSetup.configure(player, port: Int(self.vlcPort) ?? 0) {
                        if player.kind == .mpv { UserDefaults.standard.set(path, forKey: "mpvSocketPath") }
                        else { self.socketPath = path }
                    }
                }
                _ = try await BrowserSetup.launch(player.id)
                self.setupBrowserID = nil
                self.checkBrowser(player.id, force: true, askPermission: true) { state in
                    if state == .automation {
                        self.connectionDetail = "请在系统自动化设置中允许控制 \(player.name)"
                        self.waitingForBrowser = (player.id, Date().addingTimeInterval(120)); self.openAutomation()
                    } else {
                        self.connectionDetail = state.connected ? "\(player.name) 已连接，打开并播放视频即可" : "配置已写入；请在 \(player.name) 打开视频后点「检查」验证"
                        self.onShowPanel?()
                    }
                }
            } catch {
                self.setupBrowserID = nil; self.browserConnections[player.id] = .failed(error.localizedDescription)
                self.connectionDetail = error.localizedDescription; self.onShowPanel?()
            }
        }
    }

    func openAccessibility() {
        showAdvanced = false
        onHidePanel?()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openAutomation() {
        showAdvanced = false
        onHidePanel?()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    func showExtension() {
        showAdvanced = false
        onHidePanel?()
        if let url = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func showGuide() {
        showAdvanced = false
        onHidePanel?()
        if let url = Bundle.main.url(forResource: "使用说明", withExtension: "html") { NSWorkspace.shared.open(url) }
    }

    func savePassword() {
        do { try PasswordStore.save(vlcPassword); passwordStatus = vlcPassword.isEmpty ? "已移除已保存的密码" : "已保存到 macOS 钥匙串"; vlcPassword = "" }
        catch { passwordStatus = error.localizedDescription }
    }

    func copySocketPath() {
        let expanded = NSString(string: socketPath).expandingTildeInPath
        // IINA cannot create the socket unless the parent directory exists.
        let directory = URL(fileURLWithPath: expanded).deletingLastPathComponent()
        do {
            guard directory.path == NSHomeDirectory() + "/Library/Application Support/SlowFast" else {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(expanded, forType: .string); return
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(expanded, forType: .string)
            status = "已复制 IINA / mpv socket 路径"
        } catch { status = error.localizedDescription }
    }

    func perform(_ action: SpeedAction, requested: Double? = nil, origin: String = "控制台") {
        guard enabled else { return }
        guard setupBrowserID == nil else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let app = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? lastExternalApp : front
        guard let app, let id = app.bundleIdentifier, !app.isTerminated else { report(error: "请先切换到正在播放视频的应用"); return }
        guard SupportedApp.supports(id) else { report(error: "暂未适配 \(app.localizedName ?? id)，请使用支持的浏览器或播放器"); return }
        let name = app.localizedName ?? id
        targetName = name
        if extensionMode && SupportedApp.chromium.contains(id) {
            guard action != .set else { report(error: "扩展模式下，请用快捷键或浏览器工具栏选择倍速"); return }
            guard accessibilityReady else { report(error: "请先授权辅助功能，才能向浏览器发送快捷键"); return }
            guard front?.processIdentifier == app.processIdentifier else {
                report(error: "扩展模式下，请切回浏览器后使用 Fn 快捷键"); return
            }
            HotKeyListener.forwardToExtension(action)
            invalidatePlayback()
            rate = nil; status = "指令已发送；实际倍速请看网页内的 SlowFast 提示"; lastError = false
            onMenuChange?()
            return
        }
        guard pendingCount < 6 else { return }
        playbackGeneration += 1
        pendingCount += 1; busy = true
        let socket = socket(for: id)
        let port = Int(vlcPort) ?? 0
        let pid = app.processIdentifier
        worker.async { [weak self] in
            let result: Result<ControlResult, Error>
            do {
                guard let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated else { throw SlowFastError("播放器已退出") }
                let active = NSWorkspace.shared.frontmostApplication
                guard active?.processIdentifier == pid || active?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                    throw SlowFastError("前台应用已切换，已取消排队中的调速指令")
                }
                if SupportedApp.chromium.contains(id) || SupportedApp.safari.contains(id) {
                    result = .success(try AppleScriptAdapter.browser(id, action: action, requested: requested))
                } else if id == "com.apple.QuickTimePlayerX" {
                    result = .success(try AppleScriptAdapter.quickTime(action: action, requested: requested))
                } else if id == "org.videolan.vlc" {
                    result = .success(try LocalHTTP().control(port: port, password: PasswordStore.read(), action: action, requested: requested))
                } else {
                    result = .success(try MPVConnection(path: socket).control(action: action, requested: requested))
                }
            } catch { result = .failure(error) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingCount -= 1; self.busy = self.pendingCount > 0
                switch result {
                case .success(let value):
                    self.browserConnections[id] = .ready
                    if self.targetBundleID == id {
                        self.rate = value.rate; self.status = "\(name) · \(value.message)"; self.lastError = false
                        self.playbackKnown = value.isPlaying != nil
                        self.playbackPlaying = value.isPlaying == true
                    }
                    self.record(origin: origin, action: action, name: name, result: value.rate.map(SpeedScale.label) ?? "已发送")
                    self.onFeedback?(value.rate.map(SpeedScale.label) ?? "已发送", name, false)
                case .failure(let error):
                    if let scriptError = error as? AppleScriptFailure,
                       SupportedApp.safari.contains(id) || SupportedApp.chromium.contains(id) {
                        let connection = BrowserConnection.classify(number: scriptError.number, detail: scriptError.detail)
                        if connection == .javascript || connection == .automation { self.browserConnections[id] = connection }
                    }
                    self.record(origin: origin, action: action, name: name, result: error.localizedDescription)
                    if self.targetBundleID == id { self.report(error: error.localizedDescription) }
                }
                self.onMenuChange?()
            }
        }
    }

    private func record(origin: String, action: SpeedAction, name: String, result: String) {
        let labels: [SpeedAction: String] = [.faster: "加速", .slower: "减速", .reset: "恢复原速", .set: "设置倍速"]
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        recentResults.insert("\(time) · \(name) · \(origin) \(labels[action] ?? action.rawValue) → \(result)", at: 0)
        recentResults = Array(recentResults.prefix(12))
    }

    private func report(error: String) {
        invalidatePlayback()
        lastError = true; status = error; rate = nil
        onFeedback?("暂时无法调速", error, true)
        onMenuChange?()
    }
}
