import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var keepAwakeEnabled = false
    @Published private(set) var keyboardLockEnabled = false
    @Published private(set) var keyboardLockMessage: String?
    @Published private(set) var keyboardLightEnabled = true
    @Published private(set) var keyboardLightMessage: String?

    private let sleepPreventer = SleepPreventer()
    private let keyboardBlocker = KeyboardBlocker()
    private let keyboardBacklightController: KeyboardBacklightController

    init(keyboardBacklightController: KeyboardBacklightController = KeyboardBacklightController()) {
        self.keyboardBacklightController = keyboardBacklightController
    }

    var menuBarSymbolName: String {
        if keyboardLockEnabled {
            return "keyboard.badge.ellipsis"
        }

        if keepAwakeEnabled {
            return "bolt.fill"
        }

        return "bolt"
    }

    func toggleKeepAwake() {
        if keepAwakeEnabled {
            sleepPreventer.stop()
            keepAwakeEnabled = false
        } else if sleepPreventer.start() {
            keepAwakeEnabled = true
        }
    }

    func toggleKeyboardLock() {
        if keyboardLockEnabled {
            keyboardBlocker.stop()
            keyboardLockEnabled = false
            keyboardLockMessage = nil
            return
        }

        switch keyboardBlocker.start() {
        case .started:
            keyboardLockEnabled = true
            keyboardLockMessage = nil
        case .accessibilityRequired:
            keyboardLockMessage = "Allow access in System Settings > Privacy & Security > Accessibility, then try again."
        case .failed:
            keyboardLockMessage = "Could not lock the keyboard. Please try again."
        }
    }

    func toggleKeyboardLight() {
        let result = keyboardLightEnabled
            ? keyboardBacklightController.turnOff()
            : keyboardBacklightController.turnOn()

        switch result {
        case .succeeded:
            keyboardLightEnabled.toggle()
            keyboardLightMessage = nil
        case .unavailable:
            keyboardLightMessage = "Keyboard backlight control is unavailable on this Mac."
        case .failed:
            keyboardLightMessage = "Could not change the keyboard backlight. Please try again."
        }
    }
}

private final class SleepPreventer {
    private var assertionID: IOPMAssertionID = 0

    @discardableResult
    func start() -> Bool {
        guard assertionID == 0 else { return true }

        let reason = "MacGiver: keep the Mac awake" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        if result != kIOReturnSuccess {
            assertionID = 0
            return false
        }

        return true
    }

    func stop() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    deinit {
        stop()
    }
}

private final class KeyboardBlocker {
    enum StartResult {
        case started
        case accessibilityRequired
        case failed
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() -> StartResult {
        guard eventTap == nil else { return .started }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return .accessibilityRequired
        }

        let keyboardEvents = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(keyboardEvents),
            callback: keyboardEventCallback,
            userInfo: refcon
        ) else {
            return .failed
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return .failed
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return .started
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func handle(eventType: CGEventType) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return nil
        }

        switch eventType {
        case .keyDown, .keyUp, .flagsChanged:
            return nil
        default:
            return nil
        }
    }

    deinit {
        stop()
    }
}

private func keyboardEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(userInfo).takeUnretainedValue()
    return blocker.handle(eventType: type)
}
