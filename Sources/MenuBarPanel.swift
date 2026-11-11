// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import SwiftUI

private final class ControlPanel: NSPanel {
    var dismissAction: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismissAction?() }
}

final class MenuBarPanel: NSObject, NSWindowDelegate {
    private var panel: ControlPanel?
    private var localEvents: Any?
    private var outsideEvents: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var trackingMenu = false
    private weak var model: AppModel?
    private weak var anchorButton: NSStatusBarButton?
    var isVisible: Bool { panel?.isVisible == true }

    func show(model: AppModel, below button: NSStatusBarButton) {
        guard let anchorWindow = button.window, let screen = anchorWindow.screen ?? NSScreen.main else { return }
        hide()
        self.model = model
        anchorButton = button
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let top = min(anchor.minY - 6, bounds.maxY)
        let size = NSSize(width: min(400, bounds.width), height: min(568, top - bounds.minY))
        guard size.height > 160 else { return }
        let origin = NSPoint(x: max(bounds.minX, min(anchor.midX - size.width / 2, bounds.maxX - size.width)), y: top - size.height)
        let window = ControlPanel(contentRect: NSRect(origin: origin, size: size),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "SlowFast"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = false
        window.level = .statusBar
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.animationBehavior = .none
        window.delegate = self
        window.dismissAction = { [weak self] in self?.hide() }
        let host = NSHostingView(rootView: SettingsView(model: model, viewportSize: size)
            .clipShape(RoundedRectangle(cornerRadius: 22)))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.wantsLayer = true
        host.layer?.cornerRadius = 22
        host.layer?.masksToBounds = true
        window.contentView = host
        panel = window
        installDismissal()
        // A non-activating panel keeps the video app as the frontmost target.
        window.makeKeyAndOrderFront(nil)
        model.setPanelVisible(true)
    }

    func hide() {
        model?.setPanelVisible(false)
        model = nil
        if let localEvents { NSEvent.removeMonitor(localEvents) }
        if let outsideEvents { NSEvent.removeMonitor(outsideEvents) }
        localEvents = nil; outsideEvents = nil
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers.removeAll(); trackingMenu = false
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.close(); panel = nil
    }

    private var hasAlert: Bool { panel?.attachedSheet != nil || NSApp.modalWindow != nil }
    private func isOnAnchor(_ point: NSPoint) -> Bool {
        guard let button = anchorButton, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
    }
    private func installDismissal() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localEvents = NSEvent.addLocalMonitorForEvents(matching: [clicks, .keyDown]) { [weak self] event in
            guard let self, !self.trackingMenu, !self.hasAlert else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.hide(); return nil }
            } else if event.window !== self.panel && !self.isOnAnchor(NSEvent.mouseLocation) { self.hide() }
            return event
        }
        outsideEvents = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            guard let self, !self.hasAlert, !self.trackingMenu, !self.isOnAnchor(NSEvent.mouseLocation) else { return }
            self.hide()
        }
        for (name, value) in [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)] {
            menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.trackingMenu = value
            })
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.trackingMenu, !self.hasAlert, self.panel?.isKeyWindow == false else { return }
            self.hide()
        }
    }
}
