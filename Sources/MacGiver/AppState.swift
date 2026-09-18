import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var keepAwakeEnabled = false
    @Published private(set) var keyboardLockEnabled = false
    @Published private(set) var keyboardLockMessage: String?
    @Published private(set) var keyboardLightEnabled: Bool?
    @Published private(set) var keyboardLightChanging = false
    @Published private(set) var keyboardLightMessage: String?
    @Published private(set) var textExtractorShortcut: TextExtractorShortcut
    @Published private(set) var textExtractorShortcutMessage: String?

    private let sleepPreventer = SleepPreventer()
    private let keyboardBlocker = KeyboardBlocker()
    private let textExtractor = TextExtractorController()
    private let keyboardBacklightController: KeyboardBacklightController
    private let shortcutDefaults: UserDefaults
    private var globalShortcut: GlobalShortcutRegistrar?
    private static let keyboardLightReadError = String(localized: "Could not read the built-in keyboard backlight. Try again.")

    init(
        keyboardBacklightController: KeyboardBacklightController = KeyboardBacklightController(),
        registerGlobalShortcut: Bool = false,
        shortcutDefaults: UserDefaults = .standard
    ) {
        self.keyboardBacklightController = keyboardBacklightController
        self.shortcutDefaults = shortcutDefaults
        self.textExtractorShortcut = TextExtractorShortcut.load(from: shortcutDefaults)
        refreshKeyboardLight()

        guard registerGlobalShortcut else { return }

        let registrar = GlobalShortcutRegistrar { [weak self] in
            self?.beginTextExtraction()
        }
        globalShortcut = registrar
        if !registrar.register(textExtractorShortcut) {
            textExtractorShortcutMessage = String(localized: "That shortcut is already in use. Choose another one.")
        }
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
            keyboardLockMessage = String(localized: "Allow access in System Settings > Privacy & Security > Accessibility, then try again.")
        case .failed:
            keyboardLockMessage = String(localized: "Could not lock the keyboard. Please try again.")
        }
    }

    func beginTextExtraction() {
        textExtractor.begin()
    }

    @discardableResult
    func setTextExtractorShortcut(_ shortcut: TextExtractorShortcut) -> Bool {
        guard shortcut.isValid else {
            textExtractorShortcutMessage = String(localized: "Use at least one Command, Control, or Option modifier.")
            return false
        }

        if let globalShortcut, !globalShortcut.register(shortcut) {
            textExtractorShortcutMessage = String(localized: "That shortcut is already in use. Choose another one.")
            return false
        }

        shortcut.save(to: shortcutDefaults)
        textExtractorShortcut = shortcut
        textExtractorShortcutMessage = nil
        return true
    }

    func resetTextExtractorShortcut() {
        _ = setTextExtractorShortcut(.defaultValue)
    }

    func refreshKeyboardLight() {
        guard !keyboardLightChanging else { return }
        keyboardLightEnabled = keyboardBacklightController.brightness().map { $0 > 0 }
        if keyboardLightEnabled == nil {
            keyboardLightMessage = Self.keyboardLightReadError
        } else if keyboardLightMessage == Self.keyboardLightReadError {
            keyboardLightMessage = nil
        }
    }

    func retryKeyboardLight() {
        keyboardLightMessage = nil
        refreshKeyboardLight()
    }

    func setKeyboardLightEnabled(_ enabled: Bool) async {
        guard !keyboardLightChanging else { return }
        keyboardLightChanging = true
        let result = await keyboardBacklightController.setEnabled(enabled)
        keyboardLightChanging = false
        keyboardLightMessage = nil
        // Also reread on failure: a rejected or unconfirmed write may still have
        // changed the hardware. Unknown is distinct from off.
        refreshKeyboardLight()

        switch result {
        case .succeeded:
            break
        case .unavailable:
            keyboardLightMessage = Self.keyboardLightReadError
        case .failed:
            keyboardLightMessage = String(localized: "Could not confirm the keyboard brightness change. Try again.")
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
