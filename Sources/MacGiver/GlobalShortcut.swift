import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI

struct TextExtractorShortcut: Equatable {
    static let defaultValue = TextExtractorShortcut(keyCode: 26, modifiers: UInt32(cmdKey | shiftKey))

    let keyCode: UInt32
    let modifiers: UInt32
    private let keyName: String?

    init(keyCode: UInt32, modifiers: UInt32, keyName: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    var isValid: Bool {
        keyCode < 128 && modifiers & Self.primaryModifierMask != 0
    }

    var displayString: String {
        let modifierSymbols = [
            (UInt32(controlKey), "⌃"),
            (UInt32(optionKey), "⌥"),
            (UInt32(shiftKey), "⇧"),
            (UInt32(cmdKey), "⌘")
        ]
            .filter { modifiers & $0.0 != 0 }
            .map(\.1)
            .joined()

        return modifierSymbols + (keyName ?? Self.keyName(for: keyCode))
    }

    fileprivate static let primaryModifierMask = UInt32(cmdKey | controlKey | optionKey)

    fileprivate static func recorded(from event: NSEvent) -> TextExtractorShortcut {
        let modifiers = Self.carbonModifiers(for: event.modifierFlags)
        let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyName = characters.flatMap { value in
            guard value.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E }) else { return nil }
            return value.isEmpty ? nil : value.uppercased()
        }
            ?? Self.keyName(for: UInt32(event.keyCode))
        return TextExtractorShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyName: keyName)
    }

    fileprivate static func carbonModifiers(for flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    fileprivate static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key \(keyCode)"
        }
    }

    static func load(from defaults: UserDefaults) -> TextExtractorShortcut {
        guard let keyCode = defaults.object(forKey: Keys.keyCode) as? NSNumber,
              let modifiers = defaults.object(forKey: Keys.modifiers) as? NSNumber
        else {
            return .defaultValue
        }

        let keyName = defaults.string(forKey: Keys.keyName)
        let shortcut = TextExtractorShortcut(
            keyCode: keyCode.uint32Value,
            modifiers: modifiers.uint32Value,
            keyName: keyName
        )
        return shortcut.isValid ? shortcut : .defaultValue
    }

    func save(to defaults: UserDefaults) {
        defaults.set(Int(keyCode), forKey: Keys.keyCode)
        defaults.set(Int(modifiers), forKey: Keys.modifiers)
        defaults.set(keyName, forKey: Keys.keyName)
    }

    private enum Keys {
        static let keyCode = "textExtractor.shortcut.keyCode"
        static let modifiers = "textExtractor.shortcut.modifiers"
        static let keyName = "textExtractor.shortcut.keyName"
    }
}

final class GlobalShortcutRegistrar {
    private static let signature = OSType(0x4D474B52) // "MGKR"
    private static let identifier = EventHotKeyID(signature: signature, id: 1)

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var registeredShortcut: TextExtractorShortcut?
    private var handlerInstalled = false
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        installEventHandler()
    }

    @discardableResult
    func register(_ shortcut: TextExtractorShortcut) -> Bool {
        guard shortcut.isValid, handlerInstalled else { return false }

        let previousShortcut = registeredShortcut
        unregister()

        if registerWithoutReplacing(shortcut) {
            return true
        }

        if let previousShortcut {
            _ = registerWithoutReplacing(previousShortcut)
        }
        return false
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
        registeredShortcut = nil
    }

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func registerWithoutReplacing(_ shortcut: TextExtractorShortcut) -> Bool {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            Self.identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else { return false }
        hotKey = reference
        registeredShortcut = shortcut
        return true
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalShortcutEventHandler,
            1,
            &eventType,
            refcon,
            &eventHandler
        )
        handlerInstalled = status == noErr && eventHandler != nil
    }

    fileprivate func handle(event: EventRef) {
        var receivedID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &receivedID
        )
        guard status == noErr,
              receivedID.signature == Self.signature,
              receivedID.id == Self.identifier.id
        else { return }

        onTrigger()
    }
}

private func globalShortcutEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    let registrar = Unmanaged<GlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
    registrar.handle(event: event)
    return noErr
}

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: TextExtractorShortcut
    let onChange: (TextExtractorShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onChange = onChange
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.onChange = onChange
        nsView.shortcut = shortcut
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut = TextExtractorShortcut.defaultValue {
        didSet { updateTitle() }
    }

    var onChange: ((TextExtractorShortcut) -> Void)?

    private var isRecording = false {
        didSet { updateTitle() }
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        alignment = .center
        font = .systemFont(ofSize: 12, weight: .medium)
        setAccessibilityLabel(String(localized: "Text Extractor Shortcut"))
        updateTitle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        updateTitle()
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            isRecording = false
            return
        }

        let shortcut = TextExtractorShortcut.recorded(from: event)
        guard shortcut.modifiers & TextExtractorShortcut.primaryModifierMask != 0 else {
            NSSound.beep()
            return
        }

        onChange?(shortcut)
        isRecording = false
    }

    private func updateTitle() {
        title = isRecording ? String(localized: "Press a shortcut…") : shortcut.displayString
        setAccessibilityValue(title)
    }
}
