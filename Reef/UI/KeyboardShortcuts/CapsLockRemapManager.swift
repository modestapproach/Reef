//
//  CapsLockRemapManager.swift
//  Reef
//
//  Remaps Caps Lock to act as a modifier-key combination while held, without
//  any kernel driver: the HID system remaps Caps Lock → F18 (the same
//  mechanism as `hidutil property --set`), and a CGEventTap swallows F18 and
//  ORs the chosen modifier flags onto other key events while it is down.
//  Requires the Input Monitoring permission for the event tap.
//

import AppKit
import Foundation
import IOKit.hid

@MainActor
final class CapsLockRemapManager: ObservableObject {
    @Published private(set) var hasInputMonitoring =
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var capsHeld = false
    private var activeFlags: CGEventFlags = []

    private static let capsLockUsage = "0x700000039"
    private static let f18Usage = "0x70000006D"
    private static let f18KeyCode: Int64 = 79

    private var defaults: UserDefaults { .standard }

    var remapEnabled: Bool { defaults.bool(forKey: "capsLockRemapEnabled") }

    private var selectedFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if defaults.object(forKey: "capsLockControl") == nil || defaults.bool(forKey: "capsLockControl") {
            flags.insert(.maskControl)
        }
        if defaults.object(forKey: "capsLockOption") == nil || defaults.bool(forKey: "capsLockOption") {
            flags.insert(.maskAlternate)
        }
        if defaults.bool(forKey: "capsLockShift") {
            flags.insert(.maskShift)
        }
        if defaults.bool(forKey: "capsLockCommand") {
            flags.insert(.maskCommand)
        }
        return flags
    }

    func refreshAccess() {
        hasInputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    // Triggers the system Input Monitoring prompt and registers Reef in the list.
    func requestAccess() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshAccess()
    }

    func apply() {
        activeFlags = selectedFlags

        if remapEnabled {
            setHIDMapping(true)
            startTap()
        } else {
            stopTap()
            setHIDMapping(false)
            capsHeld = false
        }
    }

    // Clear the HID remap when Reef quits so Caps Lock doesn't stay a dead
    // key; it is re-applied on next launch.
    func tearDownForQuit() {
        guard remapEnabled else { return }
        stopTap()
        setHIDMapping(false)
    }

    // MARK: - HID layer

    // The HID-level remap (Caps Lock → F18) survives only until reboot or
    // keyboard re-plug, so it is re-applied on every launch and toggle.
    // NOTE: this overwrites any other UserKeyMapping set via hidutil.
    private func setHIDMapping(_ enabled: Bool) {
        let mapping = enabled
            ? #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\#(Self.capsLockUsage),"HIDKeyboardModifierMappingDst":\#(Self.f18Usage)}]}"#
            : #"{"UserKeyMapping":[]}"#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", mapping]
        try? process.run()
    }

    // MARK: - Event tap

    private func startTap() {
        guard eventTap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<CapsLockRemapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Tap creation fails without Input Monitoring; prompt so the user
            // can grant it (the preferences banner explains the rest).
            requestAccess()
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The tap runs on the main run loop, so this is main-thread in practice.
        MainActor.assumeIsolated {
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)

            case .keyDown, .keyUp:
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

                // Caps Lock arrives as F18 thanks to the HID remap. Swallow it
                // and track held state.
                if keyCode == Self.f18KeyCode {
                    capsHeld = (type == .keyDown)
                    return nil
                }

                if capsHeld {
                    event.flags.insert(activeFlags)
                }
                return Unmanaged.passUnretained(event)

            default:
                return Unmanaged.passUnretained(event)
            }
        }
    }
}
