import Charts
import SwiftUI

private enum StorageStyle {
    static let blue = MacGiverPalette.accent
    static let violet = MacGiverPalette.violet
}

struct StorageMenuPanel: View {
    @EnvironmentObject private var monitor: StorageMonitor
    private let onCollapse: () -> Void
    @State private var range = 15
    private var reading: StorageReading { monitor.reading }

    init(onCollapse: @escaping () -> Void = {}) {
        self.onCollapse = onCollapse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailHeader
            storageSummary

            if reading.availability == .available {
                stats
                history
            } else {
                unavailable
            }
        }
        .task {
            monitor.refreshStorage()
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
                Text("Storage details")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Live storage usage on this Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            Button {
                monitor.refreshStorage()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Refresh storage and history")
            .accessibilityLabel("Refresh storage and history")
        }
    }

    private var storageSummary: some View {
        StorageMenuCard {
            HStack(spacing: 9) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(StorageStyle.blue)
                    .frame(width: 36, height: 36)
                    .background(StorageStyle.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Startup disk").font(.headline)
                    Text("Storage used").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 5) {
                        Circle().fill(StorageStyle.blue).frame(width: 5, height: 5)
                        Text("LIVE").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1)
                            .foregroundStyle(StorageStyle.blue)
                    }
                    Text(reading.usedPercentText)
                        .font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                }
            }
            if let percent = reading.usedPercent {
                ProgressView(value: percent, total: 100).tint(StorageStyle.blue).padding(.top, 10)
            }
            HStack(spacing: 10) {
                StorageMetric(title: "Free space", value: reading.freeText, symbol: "internaldrive")
                StorageMetric(title: "Total capacity", value: reading.totalText, symbol: "chart.bar.xaxis")
            }
            .padding(.top, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Storage \(reading.usedPercentText) used, \(reading.freeText) available")
    }

    private var stats: some View {
        StorageMenuCard {
            HStack(spacing: 10) {
                StorageStat(title: "Used", value: reading.usedText, symbol: "arrow.up.right", tint: StorageStyle.blue)
                StorageStat(title: "Available", value: reading.freeText, symbol: "arrow.down.left", tint: StorageStyle.violet)
                StorageStat(title: "Total", value: reading.totalText, symbol: "internaldrive", tint: .secondary)
            }
        }
    }

    private var history: some View {
        StorageMenuCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Storage history").font(.subheadline.weight(.semibold))
                Picker("Storage range", selection: $range) {
                    Text("15m").tag(15)
                    Text("1h").tag(60)
                    Text("6h").tag(360)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            CompactStorageChart(history: monitor.history, reading: reading, minutes: range)
            Text("Usage sampled while MacGiver is running.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var unavailable: some View {
        StorageMenuCard {
            Label {
                Text("Storage unavailable")
            } icon: {
                Image(systemName: "internaldrive")
            }
            .font(.subheadline.weight(.medium))
            Text("Mac storage history will appear when readings become available.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 3)
        }
    }
}

struct StorageCollapsedSummary: View {
    @EnvironmentObject private var monitor: StorageMonitor
    let onExpand: () -> Void

    private var isAvailable: Bool { monitor.reading.availability == .available }

    var body: some View {
        Button(action: onExpand) {
            SummaryTile(
                title: "Storage", symbol: "internaldrive.fill",
                value: isAvailable ? monitor.reading.freeText : "—",
                status: isAvailable ? String(localized: "Free space") : String(localized: "Storage unavailable"),
                detail: isAvailable ? String(localized: "\(monitor.reading.usedPercentText) used", comment: "Used disk percentage in the compact storage tile.") : "",
                progress: isAvailable ? monitor.reading.usedPercent : nil,
                tint: StorageStyle.blue
            )
        }
        .buttonStyle(SummaryButtonStyle(tint: StorageStyle.blue))
        .help("Show storage details")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isAvailable
            ? Text("Storage \(monitor.reading.usedPercentText) used, \(monitor.reading.freeText) available. Show storage details")
            : Text("Storage unavailable"))
        .accessibilityHint("Show storage details")
    }
}

private struct StorageMetric: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).textCase(.uppercase).font(.system(size: 8, weight: .semibold)).tracking(0.7)
                    .foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.medium)).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StorageStat: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold)).foregroundStyle(tint)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompactStorageChart: View {
    let history: StorageHistory
    let reading: StorageReading
    let minutes: Int
    @State private var hoveredDate: Date?

    private var start: Date { reading.date.addingTimeInterval(-Double(minutes * 60)) }
    private var points: [StorageHistory.Point] { history.points(since: start) }
    private var domain: ClosedRange<Date> {
        let end = max(reading.date, points.last?.date ?? reading.date)
        return start...max(end, start.addingTimeInterval(60))
    }
    private var selected: StorageHistory.Point? {
        guard let hoveredDate else { return nil }
        let point = points.min { abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate)) }
        return point.flatMap { abs($0.date.timeIntervalSince(hoveredDate)) <= 10 ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Usage").font(.caption.weight(.medium))
                Spacer()
                Text(valueText).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(StorageStyle.blue)
            }
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value(String(localized: "Time"), point.date),
                             y: .value(String(localized: "Usage"), point.value),
                             series: .value(String(localized: "Segment"), point.segment))
                        .foregroundStyle(LinearGradient(colors: [StorageStyle.blue.opacity(0.22), StorageStyle.blue.opacity(0.01)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                    LineMark(x: .value(String(localized: "Time"), point.date),
                             y: .value(String(localized: "Usage"), point.value),
                             series: .value(String(localized: "Segment"), point.segment))
                        .foregroundStyle(StorageStyle.blue).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.linear)
                }
                ForEach(isolatedPoints) { point in
                    PointMark(x: .value(String(localized: "Time"), point.date), y: .value(String(localized: "Usage"), point.value))
                        .foregroundStyle(StorageStyle.blue).symbolSize(16)
                }
                if let point = selected ?? points.last {
                    PointMark(x: .value(String(localized: "Time"), point.date), y: .value(String(localized: "Usage"), point.value))
                        .foregroundStyle(StorageStyle.blue).symbolSize(24)
                }
                if let selected {
                    RuleMark(x: .value(String(localized: "Selected time"), selected.date))
                        .foregroundStyle(.secondary.opacity(0.35)).lineStyle(StrokeStyle(dash: [3, 3]))
                }
            }
            .chartXScale(domain: domain).chartYScale(domain: 0...100)
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
                    Text("Waiting for storage readings…")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(height: 82)
        }
        .padding(.top, 10)
    }

    private var isolatedPoints: [StorageHistory.Point] {
        Dictionary(grouping: points, by: \.segment).values
            .filter { $0.count == 1 }
            .compactMap(\.first)
    }

    private var valueText: String {
        if let selected { return BatteryReading.formatPercent(selected.value) }
        return reading.usedPercentText
    }
}

private struct StorageMenuCard<Content: View>: View {
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
