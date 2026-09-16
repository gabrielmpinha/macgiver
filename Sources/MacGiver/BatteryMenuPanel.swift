import Charts
import SwiftUI

private enum BatteryStyle {
    static let mint = MacGiverPalette.success
    static let violet = MacGiverPalette.violet
}

struct BatteryMenuPanel: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    private let onCollapse: () -> Void
    @State private var range = 15
    private var reading: BatteryReading { monitor.reading }

    init(onCollapse: @escaping () -> Void = {}) {
        self.onCollapse = onCollapse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailHeader
            batterySummary

            if reading.availability == .available {
                stats
                history
            } else {
                unavailable
            }
        }
        .task {
            monitor.refreshBattery()
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
            Button(action: onCollapse) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back to quick controls")
            .accessibilityLabel("Back to quick controls")

            VStack(alignment: .leading, spacing: 2) {
                Text("Battery details")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Live readings from this Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                monitor.refreshBattery()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Refresh battery and history")
            .accessibilityLabel("Refresh battery and history")
        }
    }

    private var batterySummary: some View {
        BatteryMenuCard {
            HStack(spacing: 9) {
                Image(systemName: batterySymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(BatteryStyle.mint)
                    .frame(width: 36, height: 36)
                    .background(BatteryStyle.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mac battery").font(.headline)
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
                        .font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                }
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

    private var batterySymbol: String {
        switch reading.state {
        case .charging: return "battery.75percent"
        case .charged: return "battery.100percent"
        default: return "battery.50percent"
        }
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

    private var unavailable: some View {
        BatteryMenuCard {
            Label(reading.availability == .noBattery ? "No built-in battery" : "Battery unavailable",
                  systemImage: "battery.0percent").font(.subheadline.weight(.medium))
            Text("Mac battery history will appear when readings become available.")
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
                    Image(systemName: collapsedBatterySymbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(BatteryStyle.mint)
                        .frame(width: 35, height: 35)
                        .background(BatteryStyle.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Mac battery").font(.headline)
                        Text(monitor.reading.state.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(monitor.reading.percentText)
                            .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                        HStack(spacing: 3) {
                            Text("DETAILS")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .tracking(0.7)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(.secondary)
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

    private var collapsedBatterySymbol: String {
        switch monitor.reading.state {
        case .charging: return "battery.75percent"
        case .charged: return "battery.100percent"
        default: return "battery.50percent"
        }
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
        let end = max(reading.date, points.last?.date ?? reading.date)
        return start...max(end, start.addingTimeInterval(60))
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
                        .interpolationMethod(.linear)
                    LineMark(x: .value("Time", point.date), y: .value("Value", point.value),
                             series: .value("Segment", point.segment))
                        .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.linear)
                }
                ForEach(isolatedPoints) { point in
                    PointMark(x: .value("Time", point.date), y: .value("Value", point.value))
                        .foregroundStyle(tint).symbolSize(16)
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
                if points.isEmpty {
                    Text(power ? "Waiting for power readings…" : "Waiting for battery readings…")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(height: 82)
        }
        .padding(.top, 10)
    }

    private var isolatedPoints: [BatteryHistory.Point] {
        Dictionary(grouping: points, by: \.segment).values
            .filter { $0.count == 1 }
            .compactMap(\.first)
    }

    private var valueText: String {
        if let selected {
            return power ? String(format: "%+.1f W", selected.value) : "\(Int(selected.value.rounded()))%"
        }
        return power ? reading.watts.map { String(format: "%+.1f W", $0) } ?? "—" : reading.percentText
    }
}

private struct BatteryMenuCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07))
            }
    }
}
