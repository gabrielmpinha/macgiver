import Charts
import SwiftUI

private enum BatteryStyle {
    static let mint = Color(red: 0.12, green: 0.64, blue: 0.53)
    static let violet = Color(red: 0.53, green: 0.43, blue: 0.88)
}

struct BatteryMenuPanel: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    private let onCollapse: () -> Void
    @State private var range = 15
    @State private var showingDeviceHelp = false
    private var reading: BatteryReading { monitor.reading }

    init(onCollapse: @escaping () -> Void = {}) {
        self.onCollapse = onCollapse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            batterySummary

            if reading.availability == .available {
                stats
                history
            } else {
                unavailable
            }

            devices
        }
        .task {
            monitor.refreshBattery()
            monitor.refreshDevices()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
                monitor.refreshDevices()
            }
        }
    }

    private var batterySummary: some View {
        BatteryMenuCard {
            HStack(spacing: 9) {
                Image(systemName: reading.state == .charging ? "bolt.fill" : "battery.100percent")
                    .font(.title3).foregroundStyle(BatteryStyle.mint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Battery").font(.headline)
                    Text(reading.state.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 5) {
                        Circle().fill(BatteryStyle.mint).frame(width: 5, height: 5)
                        Text("LIVE").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1)
                            .foregroundStyle(BatteryStyle.mint)
                    }
                    Text(reading.percentText)
                        .font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .help("Collapse battery details")
                .accessibilityLabel("Collapse battery details")
            }
            if let percent = reading.percent {
                ProgressView(value: percent, total: 100).tint(BatteryStyle.mint).padding(.top, 10)
            }
            HStack(spacing: 10) {
                MenuMetric(title: reading.timeTitle, value: reading.timeText, symbol: "clock")
                MenuMetric(title: "Battery power", value: reading.watts.map { String(format: "%+.1f W", $0) } ?? "—",
                           symbol: (reading.watts ?? 0) < 0 ? "arrow.down.left" : "arrow.up.right")
            }
            .padding(.top, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Battery \(reading.percentText), \(reading.state.rawValue), \(reading.timeText), \(reading.powerText)")
    }

    private var stats: some View {
        HStack(spacing: 10) {
            BatteryMenuCard {
                Label("Health", systemImage: "leaf")
                    .font(.caption.weight(.semibold)).foregroundStyle(BatteryStyle.mint)
                if let health = reading.healthPercent {
                    Text("\(Int(health.rounded()))%")
                        .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                    ProgressView(value: health, total: 100).tint(BatteryStyle.mint)
                } else {
                    Text("—").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("Unavailable").font(.caption2).foregroundStyle(.secondary)
                }
                Text("Original capacity").font(.caption2).foregroundStyle(.secondary)
            }
            .help("Estimated capacity compared with the battery's design capacity.")

            BatteryMenuCard {
                Label("Cycles", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold)).foregroundStyle(BatteryStyle.violet)
                Text(reading.cycles.map(String.init) ?? "—")
                    .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("Total battery cycles").font(.caption2).foregroundStyle(.secondary)
            }
            .help("One cycle equals using 100% of the battery's capacity, across one or more charges.")
        }
    }

    private var history: some View {
        BatteryMenuCard {
            HStack {
                Text("Energy history").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("History range", selection: $range) {
                    Text("15m").tag(15)
                    Text("1h").tag(60)
                    Text("6h").tag(360)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 142)
            }
            CompactBatteryChart(history: monitor.history, reading: reading, minutes: range, power: false)
            CompactBatteryChart(history: monitor.history, reading: reading, minutes: range, power: true)
            Text("Positive power = leaving battery · negative = charging")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var devices: some View {
        BatteryMenuCard {
            HStack(spacing: 8) {
                Label("Connected devices", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if monitor.refreshingDevices { ProgressView().controlSize(.small).scaleEffect(0.7) }
                Button { showingDeviceHelp.toggle() } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.plain).help("Device battery support")
                    .accessibilityLabel("Device battery support")
                    .popover(isPresented: $showingDeviceHelp) { deviceHelp }
                Button { monitor.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(monitor.refreshingDevices).help("Refresh devices")
                    .accessibilityLabel("Refresh connected devices")
            }

            if let scan = monitor.deviceScan {
                if scan.bluetoothUnavailable {
                    Label("Bluetooth readings unavailable", systemImage: "exclamationmark.circle")
                        .font(.caption2).foregroundStyle(.orange).padding(.top, 8)
                }
                if scan.devices.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "headphones").font(.title3).foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No battery devices connected").font(.caption.weight(.medium))
                            Text("Bluetooth accessories and USB iPhone/iPad devices appear here.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 10)
                } else {
                    VStack(spacing: 8) {
                        ForEach(scan.devices) { device in DeviceBatteryTile(device: device) }
                    }
                    .padding(.top, 10)
                }
                HStack {
                    Text("Connected only")
                    Spacer()
                    Text(scan.date.formatted(date: .omitted, time: .shortened))
                }
                .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Checking connected devices…").font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 14)
            }
        }
    }

    private var deviceHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device support").font(.headline)
            Text("Bluetooth accessories share levels when available. AirPods may show separate left, right, and case readings.")
            Text("For USB iPhone and iPad levels, install libimobiledevice, unlock the device, and trust this Mac in Finder.")
            if monitor.deviceScan?.phoneHelperAvailable != true {
                Text("brew install libimobiledevice").font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }
            Text("Apple Watch battery details and accessory health are not exposed by these connections.")
                .foregroundStyle(.secondary)
        }
        .font(.callout).padding(16).frame(width: 300)
    }

    private var unavailable: some View {
        BatteryMenuCard {
            Label(reading.availability == .noBattery ? "No built-in battery" : "Battery unavailable",
                  systemImage: "battery.0percent").font(.subheadline.weight(.medium))
            Text("Connected device readings are still checked below.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 3)
        }
    }
}

struct BatteryCollapsedSummary: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            BatteryMenuCard {
                HStack(spacing: 9) {
                    Image(systemName: monitor.reading.state == .charging ? "bolt.fill" : "battery.100percent")
                        .font(.title3).foregroundStyle(BatteryStyle.mint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Battery").font(.headline)
                        Text(monitor.reading.state.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(monitor.reading.percentText)
                            .font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let percent = monitor.reading.percent {
                    ProgressView(value: percent, total: 100).tint(BatteryStyle.mint).padding(.top, 10)
                }
                HStack {
                    Label(monitor.reading.timeText, systemImage: "clock")
                    Spacer()
                    Text(monitor.reading.watts.map { String(format: "%+.1f W", $0) } ?? "—")
                        .monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
            }
        }
        .buttonStyle(.plain)
        .help("Show battery details")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(monitor.reading.percentText), \(monitor.reading.state.rawValue), \(monitor.reading.timeText). Show battery details")
        .accessibilityAddTraits(.isButton)
    }
}

private struct MenuMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(0.7)
                    .foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.medium)).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompactBatteryChart: View {
    let history: BatteryHistory
    let reading: BatteryReading
    let minutes: Int
    let power: Bool
    @State private var hoveredDate: Date?
    private var tint: Color { power ? BatteryStyle.violet : BatteryStyle.mint }
    private var start: Date { reading.date.addingTimeInterval(-Double(minutes * 60)) }
    private var points: [BatteryHistory.Point] { history.points(since: start, power: power) }
    private var domain: ClosedRange<Date> {
        let first = points.first?.date ?? reading.date
        return max(start, min(first, reading.date.addingTimeInterval(-60)))...reading.date
    }
    private var yDomain: ClosedRange<Double> {
        guard power else { return 0...100 }
        let values = points.map(\.value)
        return min(0, (values.min() ?? 0) * 1.2)...max(5, (values.max() ?? 0) * 1.2)
    }
    private var selected: BatteryHistory.Point? {
        guard let hoveredDate else { return nil }
        let point = points.min { abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate)) }
        return point.flatMap { abs($0.date.timeIntervalSince(hoveredDate)) <= 10 ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(power ? "Battery power" : "Charge level").font(.caption.weight(.medium))
                Spacer()
                Text(valueText).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
            }
            Chart {
                if power { RuleMark(y: .value("Zero", 0)).foregroundStyle(.secondary.opacity(0.25)) }
                ForEach(points) { point in
                    AreaMark(x: .value("Time", point.date), y: .value("Value", point.value),
                             series: .value("Segment", point.segment))
                        .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.01)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", point.date), y: .value("Value", point.value),
                             series: .value("Segment", point.segment))
                        .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                if let point = selected ?? points.last {
                    PointMark(x: .value("Time", point.date), y: .value("Value", point.value))
                        .foregroundStyle(tint).symbolSize(24)
                }
                if let selected {
                    RuleMark(x: .value("Selected time", selected.date))
                        .foregroundStyle(.secondary.opacity(0.35)).lineStyle(StrokeStyle(dash: [3, 3]))
                }
            }
            .chartXScale(domain: domain).chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: domain.upperBound.timeIntervalSince(domain.lowerBound) < 300
                                   ? .dateTime.minute().second() : .dateTime.hour().minute())
                }
            }
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoveredDate = proxy.value(atX: location.x - geometry[proxy.plotAreaFrame].origin.x)
                            case .ended: hoveredDate = nil
                            }
                        }
                }
            }
            .overlay {
                if points.isEmpty { Text("Collecting readings…").font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(height: 82)
        }
        .padding(.top, 10)
    }

    private var valueText: String {
        if let selected {
            return power ? String(format: "%+.1f W", selected.value) : "\(Int(selected.value.rounded()))%"
        }
        return power ? reading.watts.map { String(format: "%+.1f W", $0) } ?? "—" : reading.percentText
    }
}

private struct DeviceBatteryTile: View {
    let device: DeviceBattery

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: device.symbol).font(.title3).foregroundStyle(BatteryStyle.violet).frame(width: 25)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(device.name).font(.caption.weight(.medium)).lineLimit(1).help(device.name)
                    Text(device.transport + (device.charging == true ? " · Charging" : ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if device.levels.isEmpty {
                    Text(device.note ?? "Battery level not reported").font(.caption2).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 9) {
                        ForEach(device.levels) { level in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 2) {
                                    Text(level.name).font(.caption2).foregroundStyle(.secondary)
                                    Text("\(Int(level.percent.rounded()))%").font(.caption2).monospacedDigit()
                                }
                                ProgressView(value: level.percent, total: 100)
                                    .tint(level.percent <= 20 ? .orange : BatteryStyle.mint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct BatteryMenuCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.055)))
    }
}
