import Foundation
import ObjectiveC

@MainActor
final class KeyboardBacklightController {
    enum Result {
        case succeeded
        case unavailable
        case failed
    }

    private let readBrightness: () -> Double?
    private let writeBrightness: (Double) -> Bool
    private var savedBrightness: Double?

    convenience init() {
        let backlight = CoreBrightnessKeyboardBacklight()
        self.init(
            readBrightness: { backlight?.brightness() },
            writeBrightness: { backlight?.setBrightness($0) ?? false }
        )
    }

    init(readBrightness: @escaping () -> Double?, writeBrightness: @escaping (Double) -> Bool) {
        self.readBrightness = readBrightness
        self.writeBrightness = writeBrightness
    }

    func brightness() -> Double? {
        guard let value = readBrightness(), value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }

    func setEnabled(_ enabled: Bool) async -> Result {
        guard let current = brightness() else { return .unavailable }

        // Repeated requests must not overwrite a stored brightness with zero or
        // replace a brightness the user has selected outside MacGiver.
        if enabled == (current > 0) {
            if enabled { savedBrightness = nil }
            return .succeeded
        }
        if !enabled { savedBrightness = current }
        let target = enabled ? (savedBrightness ?? 0.5) : 0
        guard writeBrightness(target) else { return .failed }

        // CoreBrightness applies changes asynchronously. An accepted command alone
        // is not proof that the backlight changed. Allow up to 500 ms for readback.
        for attempt in 0...10 {
            if let actual = brightness(),
               (enabled ? actual > 0 && abs(actual - target) <= 0.001 : actual == 0) {
                if enabled { savedBrightness = nil }
                return .succeeded
            }
            guard attempt < 10, !Task.isCancelled else { break }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                break
            }
        }
        return .failed
    }
}

/// CoreBrightness is a private system framework. Validate the Objective-C ABI
/// before calling it so a missing or changed interface is reported as unavailable.
/// Keyboard Backlight is an HID *device*, not an IOHID event service; its brightness
/// property must be sent through BrightnessSystemClient to reach the hardware.
@MainActor
private final class CoreBrightnessKeyboardBacklight {
    private typealias CopyIDs = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    private typealias IsBuiltIn = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias CopyBrightness = @convention(c) (AnyObject, Selector, NSString, UInt64) -> Unmanaged<AnyObject>?
    private typealias SetBrightness = @convention(c) (AnyObject, Selector, NSNumber, NSString, UInt64) -> Bool

    private static let frameworkLoaded = Bundle(
        path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"
    )?.load() == true
    private static let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
    private static let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
    private static let readSelector = NSSelectorFromString("copyPropertyForKey:keyboardID:")
    private static let writeSelector = NSSelectorFromString("setProperty:withKey:keyboardID:")
    private static let brightnessKey = "KeyboardBacklightBrightness" as NSString

    private let keyboardClient: NSObject
    private let systemClient: NSObject
    private let copyIDs: CopyIDs
    private let isBuiltIn: IsBuiltIn
    private let copyBrightness: CopyBrightness
    private let setBrightness: SetBrightness

    init?() {
        guard Self.frameworkLoaded,
              let keyboardClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type,
              let systemClass = NSClassFromString("BrightnessSystemClient") as? NSObject.Type,
              let ids = Self.method(keyboardClass, Self.idsSelector, returns: ["@"], arguments: []),
              let builtIn = Self.method(keyboardClass, Self.builtInSelector, returns: ["B"], arguments: ["Q"]),
              let read = Self.method(systemClass, Self.readSelector, returns: ["@"], arguments: ["@", "Q"]),
              let write = Self.method(systemClass, Self.writeSelector, returns: ["B"], arguments: ["@", "@", "Q"])
        else { return nil }

        keyboardClient = keyboardClass.init()
        systemClient = systemClass.init()
        copyIDs = unsafeBitCast(method_getImplementation(ids), to: CopyIDs.self)
        isBuiltIn = unsafeBitCast(method_getImplementation(builtIn), to: IsBuiltIn.self)
        copyBrightness = unsafeBitCast(method_getImplementation(read), to: CopyBrightness.self)
        setBrightness = unsafeBitCast(method_getImplementation(write), to: SetBrightness.self)
    }

    private func keyboardID() -> UInt64? {
        // Objective-C copy-family methods return owned objects. Transfer ownership
        // to ARC, and enumerate again so wake/hardware re-registration can recover.
        guard let ids = copyIDs(keyboardClient, Self.idsSelector)?.takeRetainedValue() as? [NSNumber] else {
            return nil
        }
        return ids.first { isBuiltIn(keyboardClient, Self.builtInSelector, $0.uint64Value) }?.uint64Value
    }

    func brightness() -> Double? {
        guard let id = keyboardID(),
              let value = copyBrightness(systemClient, Self.readSelector, Self.brightnessKey, id)?
                .takeRetainedValue() as? NSNumber else { return nil }
        return value.doubleValue
    }

    func setBrightness(_ value: Double) -> Bool {
        guard value.isFinite, (0...1).contains(value), let id = keyboardID() else { return false }
        return setBrightness(systemClient, Self.writeSelector, NSNumber(value: value), Self.brightnessKey, id)
    }

    private static func method(
        _ type: AnyClass, _ selector: Selector, returns returnTypes: Set<String>, arguments: [String]
    ) -> Method? {
        guard let method = class_getInstanceMethod(type, selector),
              method_getNumberOfArguments(method) == arguments.count + 2 else { return nil }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard returnTypes.contains(String(cString: returnType)) else { return nil }
        for (index, expected) in (["@", ":"] + arguments).enumerated() {
            guard let actual = method_copyArgumentType(method, UInt32(index)) else { return nil }
            defer { free(actual) }
            guard String(cString: actual) == expected else { return nil }
        }
        return method
    }
}
