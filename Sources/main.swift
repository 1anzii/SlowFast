// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var statusItem: NSStatusItem!
    let panel = MenuBarPanel()
    let preferences = PreferencesWindow()
    var screenObserver: NSObjectProtocol?
    var hud: NSPanel?
    var hideHUD: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SlowFastBrand.registerFont()
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.yeonza.SlowFast")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first { existing.activate(options: []); NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.setAccessibilityLabel("SlowFast")
        model.onMenuChange = { [weak self] in self?.updateStatus() }
        model.onFeedback = { [weak self] title, subtitle, error in self?.showHUD(title, subtitle: subtitle, error: error) }
        model.onHidePanel = { [weak self] in self?.panel.hide() }
        model.onShowPanel = { [weak self] in self?.showSettings() }
        model.onAdvancedChange = { [weak self] visible in
            DispatchQueue.main.async {
                guard let self, self.model.showAdvanced == visible else { return }
                if visible { self.panel.hide(); self.preferences.show(model: self.model) }
                else { self.preferences.hide() }
            }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.panel.hide() }
        model.start()
        updateStatus()
        DispatchQueue.main.async { [weak self] in self?.showSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel.hide(); preferences.hide(); model.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }

    func updateStatus() {
        let icon = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "SlowFast")
        icon?.isTemplate = true
        statusItem?.button?.image = icon
        statusItem?.button?.title = model.rate.map { " " + SpeedScale.label($0) } ?? ""
        statusItem?.button?.toolTip = "SlowFast · " + model.status
    }

    @objc func statusClicked() {
        if NSApp.currentEvent?.type != .rightMouseUp {
            if panel.isVisible { panel.hide() } else { showSettings() }
            return
        }
        panel.hide()
        let menu = NSMenu()
        let summary = NSMenuItem(title: model.targetName + " · " + (model.rate.map(SpeedScale.label) ?? "等待指令"), action: nil, keyEquivalent: "")
        menu.addItem(summary); menu.addItem(.separator())
        add(menu, "慢一点     fn ,", #selector(slower))
        add(menu, "快一点     fn .", #selector(faster))
        add(menu, "恢复 1×    fn ?", #selector(reset))
        menu.addItem(.separator())
        add(menu, model.enabled ? "暂停快捷键" : "启用快捷键", #selector(toggle))
        add(menu, "打开 SlowFast…", #selector(showSettings))
        add(menu, "使用说明", #selector(guide))
        menu.addItem(.separator())
        add(menu, "退出 SlowFast", #selector(quit))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func add(_ menu: NSMenu, _ title: String, _ selector: Selector) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
    }
    func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: "SlowFast")
        let settings = NSMenuItem(title: "SlowFast 设置…", action: #selector(showPreferences), keyEquivalent: ",")
        settings.target = self; appMenu.addItem(settings); appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 SlowFast", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; appMenu.addItem(quit); appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }
    @objc func slower() { model.perform(.slower) }
    @objc func faster() { model.perform(.faster) }
    @objc func reset() { model.perform(.reset) }
    @objc func toggle() { model.enabled.toggle() }
    @objc func guide() { model.showGuide() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showPreferences() {
        if model.showAdvanced { preferences.show(model: model) }
        else { model.showAdvanced = true }
    }

    @objc func showSettings() {
        guard let button = statusItem?.button else { return }
        model.capturePanelTarget()
        panel.show(model: model, below: button)
    }

    func showHUD(_ title: String, subtitle: String, error: Bool) {
        hideHUD?.cancel()
        if hud == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating; panel.backgroundColor = .clear; panel.isOpaque = false
            panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            hud = panel
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width: CGFloat = error ? 300 : 210
        hud?.setFrame(NSRect(x: frame.midX - width / 2, y: frame.minY + 75, width: width, height: 120), display: false)
        hud?.contentView = NSHostingView(rootView: HUDView(title: title, subtitle: subtitle, error: error))
        hud?.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.hud?.orderOut(nil) }
        hideHUD = work; DispatchQueue.main.asyncAfter(deadline: .now() + (error ? 3.5 : 1.4), execute: work)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
