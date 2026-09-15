import Foundation
import Darwin

struct DeviceBattery: Identifiable, Sendable {
    struct Level: Identifiable, Sendable {
        var id: String { name }
        let name: String
        let percent: Double
    }
    let id: String
    let name: String
    let transport: String
    let symbol: String
    var levels: [Level] = []
    var charging: Bool?
    var note: String?

    static func symbol(for name: String) -> String {
        let name = name.lowercased()
        if name.contains("iphone") { return "iphone" }
        if name.contains("ipad") { return "ipad" }
        if name.contains("watch") { return "applewatch" }
        if name.contains("airpods") { return "airpodspro" }
        if name.contains("head") { return "headphones" }
        if name.contains("mouse") { return "computermouse" }
        if name.contains("trackpad") { return "magicmouse" }
        if name.contains("keyboard") { return "keyboard" }
        return "hifispeaker"
    }
}

struct DeviceScan: Sendable {
    var devices: [DeviceBattery] = []
    var date = Date()
    var bluetoothUnavailable = false
    var phoneHelperAvailable = false
}

actor DeviceBatteryReader {
    func read() async -> DeviceScan {
        let bluetoothData = await BatteryCommand.run("/usr/sbin/system_profiler",
            arguments: ["SPBluetoothDataType", "-json", "-detailLevel", "mini"], timeout: 12)
        let bluetooth = bluetoothData.flatMap(Self.decodeBluetooth)
        var scan = DeviceScan(devices: bluetooth ?? [], bluetoothUnavailable: bluetooth == nil)

        // Only attached USB HID devices. Bluetooth connectivity comes from the profiler,
        // since a cached HID service alone does not prove a wireless device is connected.
        for (index, properties) in BatteryHardware.properties(className: "IOHIDDevice").enumerated() {
            guard properties["Transport"] as? String == "USB",
                  let percent = Self.percent(properties["BatteryPercent"]),
                  let name = properties["Product"] as? String else { continue }
            let serial = properties["SerialNumber"] as? String
            let identity = serial.flatMap { $0.isEmpty ? nil : $0 }
                ?? "\(name)-\(properties["LocationID"] ?? index)"
            let id = "usb-hid:\(identity)"
            guard !scan.devices.contains(where: { $0.id == id }) else { continue }
            scan.devices.append(DeviceBattery(id: id, name: name, transport: "USB",
                symbol: DeviceBattery.symbol(for: name), levels: [.init(name: "Battery", percent: percent)]))
        }

        let helper = ["/opt/homebrew/bin/ideviceinfo", "/usr/local/bin/ideviceinfo"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        scan.phoneHelperAvailable = helper != nil
        // Enumerating USB is read-only and works even without the optional helper.
        for properties in BatteryHardware.properties(className: "IOUSBHostDevice") {
            guard let name = properties["USB Product Name"] as? String,
                  name.localizedCaseInsensitiveContains("iPhone") || name.localizedCaseInsensitiveContains("iPad"),
                  let serial = properties["USB Serial Number"] as? String, !serial.isEmpty else { continue }
            var device = DeviceBattery(id: "ios:\(serial)", name: name, transport: "USB",
                symbol: DeviceBattery.symbol(for: name))
            if let helper, !Task.isCancelled {
                // Modern USB serials omit the dash that usbmuxd uses in the UDID.
                let udid = serial.count == 24 ? "\(serial.prefix(8))-\(serial.dropFirst(8))" : serial
                let result = await BatteryCommand.run(helper,
                    arguments: ["-s", "-u", udid, "-q", "com.apple.mobile.battery", "-x"], timeout: 4)
                if let result,
                   let values = try? PropertyListSerialization.propertyList(from: result, format: nil) as? [String: Any] {
                    device.levels = Self.phoneLevels(values)
                    device.charging = values["BatteryIsCharging"] as? Bool
                }
                if device.levels.isEmpty { device.note = "Unlock and trust this Mac to share battery readings." }
            } else {
                device.note = "Enable iPhone support to read its battery."
            }
            if !scan.devices.contains(where: { $0.id == device.id }) { scan.devices.append(device) }
        }
        scan.devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        scan.date = Date()
        return scan
    }

    static func percent(_ value: Any?) -> Double? {
        let parsed: Double?
        if let text = value as? String {
            parsed = Double(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        } else {
            parsed = BatteryReading.number(value)
        }
        guard let parsed, parsed.isFinite, (0...100).contains(parsed) else { return nil }
        return parsed
    }

    static func phoneLevels(_ properties: [String: Any]) -> [DeviceBattery.Level] {
        percent(properties["BatteryCurrentCapacity"]).map { [.init(name: "Battery", percent: $0)] } ?? []
    }

    static func decodeBluetooth(_ data: Data) -> [DeviceBattery]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        var devices: [DeviceBattery] = []
        for controller in controllers {
            // Never read device_not_connected: its values may be old cached readings.
            let connected = controller["device_connected"] as? [[String: Any]] ?? []
            for entry in connected {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let address = info["device_address"] as? String
                    let id = "bluetooth:\(address ?? name)"
                    guard !devices.contains(where: { $0.id == id }) else { continue }
                    let keys = [("device_batteryLevelMain", "Battery"), ("device_batteryLevelLeft", "Left"),
                                ("device_batteryLevelRight", "Right"), ("device_batteryLevelCase", "Case")]
                    let levels = keys.compactMap { key, label -> DeviceBattery.Level? in
                        percent(info[key]).map { .init(name: label, percent: $0) }
                    }
                    devices.append(DeviceBattery(id: id, name: name, transport: "Bluetooth",
                        symbol: DeviceBattery.symbol(for: name + " " + (info["device_minorType"] as? String ?? "")),
                        levels: levels))
                }
            }
        }
        return devices
    }
}

/// Commands run without a shell. Drain stdout without blocking, discard stderr, and bound
/// output size and runtime so a helper cannot freeze the dashboard or accumulate jobs.
enum BatteryCommand {
    static func run(_ executable: String, arguments: [String], timeout: TimeInterval) async -> Data? {
        guard !Task.isCancelled else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try? pipe.fileHandleForReading.close()
        }
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else { return nil }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var reachedEOF = false
        // Continue enforcing the deadline if a descendant holds stdout open after
        // the direct child exits. No blocking read or unbounded wait is used.
        while process.isRunning || !reachedEOF {
            guard !Task.isCancelled, clock.now < deadline else { return nil }
            if !reachedEOF {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    guard data.count + count <= 2_000_000 else { return nil }
                    data.append(contentsOf: buffer.prefix(count))
                    continue
                }
                if count == 0 { reachedEOF = true }
                if count < 0 && errno != EAGAIN && errno != EINTR { return nil }
            }
            if process.isRunning || !reachedEOF {
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return nil }
            }
        }
        return process.terminationStatus == 0 ? data : nil
    }
}
