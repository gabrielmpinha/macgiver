import CoreFoundation
import Foundation
import IOKit

final class KeyboardBacklightController {
    enum Result {
        case succeeded
        case unavailable
        case failed
    }

    private static let propertyKey = "KeyboardBacklightBrightness"
    private static let serviceClasses = [
        "AppleHIDKeyboardEventDriverV2",
        "AppleHIDKeyboardEventDriver"
    ]
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
        for serviceClass in serviceClasses {
            var iterator: io_iterator_t = 0
            guard let matching = IOServiceMatching(serviceClass),
                  IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                guard let value = IORegistryEntryCreateCFProperty(
                    service,
                    propertyKey as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? NSNumber else {
                    continue
                }
                return value.intValue
            }
        }
        return nil
    }

    private static func writeSystemBrightness(_ brightness: Int) -> Bool {
        for serviceClass in serviceClasses {
            var iterator: io_iterator_t = 0
            guard let matching = IOServiceMatching(serviceClass),
                  IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            while case let service = IOIteratorNext(iterator), service != 0 {
                let result = IORegistryEntrySetCFProperty(
                    service,
                    propertyKey as CFString,
                    NSNumber(value: brightness)
                )
                IOObjectRelease(service)
                if result == KERN_SUCCESS { return true }
            }
        }
        return false
    }
}
