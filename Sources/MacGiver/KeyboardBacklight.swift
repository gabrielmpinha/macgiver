import CoreFoundation
import Foundation
import IOKit.hidsystem

final class KeyboardBacklightController {
    enum Result {
        case succeeded
        case unavailable
        case failed
    }

    private static let propertyKey = "KeyboardBacklightBrightness"
    private static let backlightUsagePage: UInt32 = 0xFF00
    private static let backlightUsage: UInt32 = 15
    private static let defaultBrightness = 255

    private let readBrightness: () -> Int?
    private let writeBrightness: (Int) -> Bool
    private var savedBrightness: Int?

    init(
        readBrightness: @escaping () -> Int? = KeyboardBacklightController.readSystemBrightness,
        writeBrightness: @escaping (Int) -> Bool = KeyboardBacklightController.writeSystemBrightness
    ) {
        self.readBrightness = readBrightness
        self.writeBrightness = writeBrightness
    }

    func turnOff() -> Result {
        guard let brightness = readBrightness() else { return .unavailable }

        savedBrightness = brightness > 0 ? brightness : nil
        guard writeBrightness(0) else {
            savedBrightness = nil
            return .failed
        }

        return .succeeded
    }

    func turnOn() -> Result {
        guard writeBrightness(savedBrightness ?? Self.defaultBrightness) else { return .failed }
        savedBrightness = nil
        return .succeeded
    }

    private static func readSystemBrightness() -> Int? {
        forEachKeyboardService { service in
            guard let value = IOHIDServiceClientCopyProperty(
                service,
                propertyKey as CFString
            ) as? NSNumber else { return nil }
            return value.intValue
        }
    }

    private static func writeSystemBrightness(_ brightness: Int) -> Bool {
        guard let result: Bool = forEachKeyboardService({ service in
            IOHIDServiceClientSetProperty(
                service,
                propertyKey as CFString,
                NSNumber(value: brightness)
            )
        }) else { return false }
        return result
    }

    private static func forEachKeyboardService<T>(
        _ body: (IOHIDServiceClient) -> T?
    ) -> T? {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)

        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return nil
        }

        for service in services {
            // Apple's backlight endpoint is a vendor-defined HID service. Matching
            // its usage avoids accidentally selecting null properties from unrelated
            // keyboard, trackpad, and system services.
            guard IOHIDServiceClientConformsTo(
                service,
                backlightUsagePage,
                backlightUsage
            ) != 0 else {
                continue
            }

            if let result = body(service) { return result }
        }

        return nil
    }
}
