import Charts
import SwiftUI

private enum BatteryStyle {
    static let mint = Color(red: 0.12, green: 0.64, blue: 0.53)
    static let violet = Color(red: 0.53, green: 0.43, blue: 0.88)
}

struct BatteryDashboardView: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    @State private var range = 15
    @State private var showingDeviceHelp = false
    private var reading: BatteryReading { monitor.reading }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if reading.availability == .available {
                    HStack(alignment: .top, spacing: 16) {
                        overview.frame(maxWidth: .infinity)
                        health.frame(width: 256)
                    }
                    history
                } else {
                    unavailable
                }
                devices
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                    Text("Mac readings every 5 seconds · History stays on this Mac until you quit.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 860, minHeight: 620)
        .task {
            monitor.refreshBattery()
            while !Task.isCancelled {
                monitor.refreshDevices()
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Battery").font(.system(size: 32, weight: .bold, design: .rounded))
                Text("A little clarity on your everyday energy.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("MacGiver", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            if reading.availability == .available {
                HStack(spacing: 6) {
                    Circle().fill(BatteryStyle.mint).frame(width: 6, height: 6)
                    Text("LIVE").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(BatteryStyle.mint.opacity(0.10), in: Capsule())
                .accessibilityLabel("Live battery readings")
            }
        }
    }

    private var overview: some View {
        BatteryCard {
            HStack(alignment: .center, spacing: 24) {
                ZStack {
                    Circle().stroke(BatteryStyle.mint.opacity(0.12), lineWidth: 11)
                    if let percent = reading.percent {
                        Circle().trim(from: 0, to: percent / 100)
                        .stroke(AngularGradient(colors: [BatteryStyle.mint.opacity(0.5), BatteryStyle.mint],
                                                center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                                style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 5) {
                        Image(systemName: reading.state == .charging ? "bolt.fill" : "battery.100percent")
                            .foregroundStyle(BatteryStyle.mint)
                        Text(reading.percentText)
                            .font(.system(size: 33, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("CHARGE").font(.system(size: 9, weight: .semibold)).tracking(1.4)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 130, height: 130)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery charge \(reading.percentText)")
                VStack(alignment: .leading, spacing: 10) {
                    Label("THIS MAC", systemImage: "laptopcomputer")
                        .font(.system(size: 10, weight: .semibold)).tracking(1)
                        .foregroundStyle(.secondary)
                    Text(reading.state.rawValue).font(.title3.weight(.semibold))
                    Text(reading.timeText)
                        .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(reading.state == .charging ? "estimated until fully charged" :
                         reading.state == .discharging ? "estimated time remaining" : "Battery charge is managed by macOS")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            Divider().padding(.vertical, 9)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BATTERY POWER").font(.system(size: 9, weight: .semibold)).tracking(1)
                        .foregroundStyle(.secondary)
                    Text(reading.powerText).font(.system(size: 23, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                Label(reading.flowText, systemImage: (reading.watts ?? 0) < 0 ? "arrow.down.left" : "arrow.up.right")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var health: some View {
        BatteryCard {
            Label("Battery health", systemImage: "leaf")
                .font(.subheadline.weight(.semibold)).foregroundStyle(BatteryStyle.mint)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(reading.healthPercent.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: 40, weight: .medium, design: .rounded)).monospacedDigit()
                if reading.healthPercent != nil { Text("%").font(.title2).foregroundStyle(.secondary) }
                Spacer()
                if let condition = reading.condition {
                    Text(condition).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
            if let health = reading.healthPercent {
                ProgressView(value: health, total: 100).tint(BatteryStyle.mint)
                    .accessibilityLabel("Estimated battery health")
            } else {
                Text("Health reading unavailable").font(.caption).foregroundStyle(.secondary)
            }
            Text("Original capacity · estimate")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                .help("Capacity compared with the battery's design capacity. This estimate can differ from System Settings.")
            Divider().padding(.vertical, 9)
            HStack(alignment: .firstTextBaseline) {
                Text(reading.cycles.map(String.init) ?? "—")
                    .font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer()
                Text("total cycles").font(.caption).foregroundStyle(.secondary)
            }
            .help("One cycle is the use of an amount of energy equal to 100% of the battery's capacity, across one or more charges.")
            Spacer(minLength: 0)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Energy over time").font(.title3.weight(.semibold))
                Spacer()
                Picker("History range", selection: $range) {
                    Text("15 min").tag(15)
                    Text("1 hour").tag(60)
                    Text("6 hours").tag(360)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
            }
            HStack(alignment: .top, spacing: 16) {
                BatteryHistoryChart(history: monitor.history, reading: reading, minutes: range, power: false)
                BatteryHistoryChart(history: monitor.history, reading: reading, minutes: range, power: true)
            }
        }
    }

    private var devices: some View {
        BatteryCard {
            HStack {
                Label("Connected devices", systemImage: "link").font(.headline)
                Spacer()
                if monitor.refreshingDevices {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Button { showingDeviceHelp.toggle() } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain).help("Device battery support")
                .popover(isPresented: $showingDeviceHelp) { deviceHelp }
                Button { monitor.refreshDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain).disabled(monitor.refreshingDevices).help("Refresh devices")
                .accessibilityLabel("Refresh connected devices")
            }
            if let scan = monitor.deviceScan {
                if scan.bluetoothUnavailable {
                    Label("Bluetooth readings unavailable. Try refreshing.", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange).padding(.top, 12)
                }
                if scan.devices.isEmpty {
                    HStack(spacing: 14) {
                        Image(systemName: "headphones").font(.system(size: 28)).foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your devices, together here").font(.subheadline.weight(.medium))
                            Text("Connect a Bluetooth accessory or plug in an iPhone or iPad.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(scan.devices) { device in DeviceBatteryTile(device: device) }
                    }
                    .padding(.vertical, 14)
                }
                HStack {
                    Text("Only connected devices · Readings depend on device support")
                    Spacer()
                    Text("Checked \(scan.date.formatted(date: .omitted, time: .shortened))")
                }
                .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Checking connected devices…").foregroundStyle(.secondary).padding(.vertical, 22)
            }
        }
    }

    private var deviceHelp: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A note on device support").font(.headline)
            Text("Bluetooth accessories share battery levels when available. AirPods can report separate left, right, and case levels.")
            Text("For USB iPhone and iPad battery levels, install libimobiledevice, then unlock your device and trust this Mac in Finder.")
            if monitor.deviceScan?.phoneHelperAvailable != true {
                Text("brew install libimobiledevice").font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Apple Watch battery, accessory health, cycle counts, and remaining time are not exposed by these connections. Unreported values are left blank.")
                .foregroundStyle(.secondary)
        }
        .font(.callout).padding(22).frame(width: 370)
    }

    private var unavailable: some View {
        BatteryCard {
            Label(reading.availability == .noBattery ? "No built-in battery" : "Battery readings unavailable",
                  systemImage: "battery.0percent").font(.title2.weight(.medium))
            Text(reading.availability == .noBattery
                 ? "Connected accessory batteries will still appear below."
                 : "MacGiver will try again automatically. Connected devices are shown below.")
                .foregroundStyle(.secondary).padding(.top, 6)
        }
    }
}

private struct BatteryHistoryChart: View {
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
    private var selected: BatteryHistory.Point? {
        guard let hoveredDate else { return nil }
        let nearest = points.min { abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate)) }
        return nearest.flatMap { abs($0.date.timeIntervalSince(hoveredDate)) <= 10 ? $0 : nil }
    }
    private var isolatedPoints: [BatteryHistory.Point] {
        Dictionary(grouping: points, by: \.segment).values.filter { $0.count == 1 }.compactMap(\.first)
    }
    private var yDomain: ClosedRange<Double> {
        guard power else { return 0...100 }
        let values = points.map(\.value)
        return min(0, (values.min() ?? 0) * 1.2)...max(5, (values.max() ?? 0) * 1.2)
    }

    var body: some View {
        BatteryCard {
            HStack(alignment: .firstTextBaseline) {
                Text(power ? "Battery power" : "Charge level").font(.subheadline.weight(.semibold))
                Spacer()
                Text(valueText).font(.system(.headline, design: .rounded)).monospacedDigit().foregroundStyle(tint)
            }
            Chart {
                if power {
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(.secondary.opacity(0.25))
                }
                ForEach(points) { point in
                    AreaMark(x: .value("Time", point.date), y: .value(power ? "Watts" : "Charge", point.value),
                             series: .value("Segment", point.segment))
                        .foregroundStyle(LinearGradient(colors: [tint.opacity(0.24), tint.opacity(0.015)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("Time", point.date), y: .value(power ? "Watts" : "Charge", point.value),
                             series: .value("Segment", point.segment))
                        .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round))
                        .interpolationMethod(.linear)
                }
                ForEach(isolatedPoints) { point in
                    PointMark(x: .value("Time", point.date), y: .value("Reading", point.value))
                        .foregroundStyle(tint).symbolSize(16)
                }
                if let point = selected ?? points.last {
                    PointMark(x: .value("Time", point.date), y: .value("Reading", point.value))
                        .foregroundStyle(tint).symbolSize(28)
                }
                if let selected {
                    RuleMark(x: .value("Selected time", selected.date))
                        .foregroundStyle(.secondary.opacity(0.4)).lineStyle(StrokeStyle(dash: [3, 3]))
                }
            }
            .chartXScale(domain: domain).chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    if domain.upperBound.timeIntervalSince(domain.lowerBound) < 300 {
                        AxisValueLabel(format: .dateTime.minute().second())
                    } else {
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(Int(number))\(power ? " W" : "%")").font(.system(size: 9))
                        }
                    }
                }
            }
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
                if points.isEmpty {
                    Text(power ? "Waiting for power readings" : "Waiting for battery readings")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 145).padding(.top, 14)
            HStack {
                Text(selected.map { $0.date.formatted(date: .omitted, time: .standard) }
                     ?? (power ? "+ discharge / − charge" : "Recorded since \((points.first?.date ?? reading.date).formatted(date: .omitted, time: .shortened))"))
                Spacer()
                if points.count < 2 { Text("Collecting history…") }
            }
            .font(.caption2).foregroundStyle(.secondary).padding(.top, 8)
        }
    }

    private var valueText: String {
        if let selected { return power ? String(format: "%+.1f W", selected.value) : "\(Int(selected.value.rounded()))%" }
        return power ? reading.watts.map { String(format: "%+.1f W", $0) } ?? "—" : reading.percentText
    }
}

private struct DeviceBatteryTile: View {
    let device: DeviceBattery
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: device.symbol).font(.title2).foregroundStyle(BatteryStyle.violet).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name).font(.subheadline.weight(.medium)).lineLimit(1).help(device.name)
                    Text(device.transport + (device.charging == true ? " · Charging" : ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if device.levels.isEmpty {
                Text(device.note ?? "Battery level not reported")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 14) {
                    ForEach(device.levels) { level in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(level.name).foregroundStyle(.secondary)
                                Spacer(minLength: 2)
                                Text("\(Int(level.percent.rounded()))%").monospacedDigit()
                            }
                            .font(.caption2)
                            ProgressView(value: level.percent, total: 100)
                                .tint(level.percent <= 20 ? .orange : BatteryStyle.mint)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct BatteryCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.055)))
            .shadow(color: .black.opacity(0.025), radius: 12, y: 4)
    }
}

struct BatteryMenuSummary: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: "battery")
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Battery", systemImage: "battery.100percent")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(monitor.reading.percentText).monospacedDigit().fontWeight(.semibold)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                if monitor.reading.availability == .available {
                    if let percent = monitor.reading.percent {
                        ProgressView(value: percent, total: 100).tint(BatteryStyle.mint)
                    }
                    HStack {
                        Text(monitor.reading.timeText)
                        Spacer()
                        Text(monitor.reading.powerText)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Battery details & connected devices").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12).background(BatteryStyle.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("Open battery dashboard")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(monitor.reading.percentText). Open battery dashboard")
        .accessibilityAddTraits(.isButton)
    }
}
