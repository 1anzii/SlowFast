// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import SwiftUI

private final class PreferencesPanel: NSPanel {
    var dismissAction: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismissAction?() }
}

private final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowDragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

// Settings is an independent window, not a sheet attached to the status-bar panel.
// The native layer mask also clips AppKit-backed content at all four corners.
final class PreferencesWindow: NSObject, NSWindowDelegate {
    private var window: PreferencesPanel?
    private weak var model: AppModel?

    func show(model: AppModel) {
        self.model = model
        if window == nil {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let bounds = screen?.visibleFrame.insetBy(dx: 12, dy: 12) ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let size = NSSize(width: min(420, bounds.width), height: min(580, bounds.height))
            let panel = PreferencesPanel(contentRect: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height),
                                         styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = "SlowFast 设置"
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.isMovable = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.animationBehavior = .none
            panel.delegate = self
            panel.dismissAction = { [weak self] in self?.model?.showAdvanced = false }
            let host = NSHostingView(rootView: PreferencesView(model: model, viewportSize: size).clipShape(RoundedRectangle(cornerRadius: 22)))
            host.sizingOptions = []
            host.frame = NSRect(origin: .zero, size: size)
            host.wantsLayer = true
            host.layer?.cornerRadius = 22
            host.layer?.masksToBounds = true
            panel.contentView = host
            window = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() { window?.orderOut(nil) }

    func windowWillClose(_ notification: Notification) { model?.showAdvanced = false }
}
