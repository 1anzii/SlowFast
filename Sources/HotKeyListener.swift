// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import ApplicationServices

final class HotKeyListener {
    var enabled = true
    var onAction: ((SpeedAction) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var consumed = Set<Int64>()
    var running: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() -> Bool {
        if let tap, CFMachPortIsValid(tap) { CGEvent.tapEnable(tap: tap, enable: true); return running }
        stop() // Recreate a tap invalidated during sleep / permission changes.
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<HotKeyListener>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                owner.consumed.removeAll()
                return Unmanaged.passUnretained(event)
            }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if type == .keyUp, owner.consumed.remove(code) != nil { return nil }
            guard owner.enabled, type == .keyDown,
                  let action = HotKey.action(keyCode: code, flags: event.flags) else {
                return Unmanaged.passUnretained(event)
            }
            owner.consumed.insert(code)
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                DispatchQueue.main.async { owner.onAction?(action) }
            }
            return nil
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return running
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil; consumed.removeAll()
    }

    static func forwardToExtension(_ action: SpeedAction) {
        let code: CGKeyCode = action == .slower ? 43 : action == .faster ? 47 : 29
        let eventSource = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down) else { continue }
            event.flags = [.maskControl, .maskShift]
            event.post(tap: .cgSessionEventTap)
        }
    }
}
