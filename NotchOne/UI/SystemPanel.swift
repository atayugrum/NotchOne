import SwiftUI

/// System tab: CPU, memory and network with a minute of history, and device batteries.
/// Measures only while it's on screen.
struct SystemPanel: View {
    let system: SystemMonitorStore
    let devices: DeviceBatteryStore

    var body: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                GaugeCard(
                    symbol: "cpu", title: "CPU",
                    value: system.current.map { percent($0.cpu) } ?? "–",
                    detail: nil,
                    history: system.cpuHistory, maximum: 1, tint: .orange
                )
                GaugeCard(
                    symbol: "memorychip", title: "Memory",
                    value: system.current.map { percent($0.memory) } ?? "–",
                    detail: system.current.map { memoryLine($0) },
                    history: system.memoryHistory, maximum: 1, tint: .cyan
                )
                GaugeCard(
                    symbol: "arrow.up.arrow.down", title: "Network",
                    value: system.current.map { "↓ " + SystemMonitorLogic.rate($0.download) } ?? "–",
                    detail: system.current.map { "↑ " + SystemMonitorLogic.rate($0.upload) },
                    history: system.downloadHistory, maximum: max(system.downloadHistory.max() ?? 1, 1), tint: .green
                )
            }
            DeviceRow(devices: devices.devices, diskFree: system.current?.diskFree)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            system.startWatching()
            devices.refresh()
        }
        .onDisappear { system.stopWatching() }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func memoryLine(_ sample: SystemSample) -> String {
        let used = ByteCountFormatter.string(fromByteCount: Int64(sample.memoryUsed), countStyle: .memory)
        let total = ByteCountFormatter.string(fromByteCount: Int64(sample.memoryTotal), countStyle: .memory)
        return "\(used) / \(total)"
    }
}

private struct GaugeCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: String
    let detail: String?
    let history: [Double]
    let maximum: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(title, systemImage: symbol)
                .font(Typo.micro)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Typo.number(17))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(detail ?? " ")
                .font(Typo.micro)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Sparkline(values: history, maximum: maximum, tint: tint)
                .frame(height: 26)
        }
        .padding(Space.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .animation(Motion.quick, value: value)
    }
}

/// A minute of values as a line with a soft fill under it.
struct Sparkline: View {
    let values: [Double]
    let maximum: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = Self.points(values, maximum: maximum, size: proxy.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Newest on the right; a full minute spans the width.
    nonisolated static func points(_ values: [Double], maximum: Double, size: CGSize) -> [CGPoint] {
        guard !values.isEmpty, maximum > 0 else { return [] }
        let step = size.width / CGFloat(max(SystemMonitorLogic.historyLength - 1, 1))
        let start = size.width - step * CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: start + step * CGFloat(index), y: size.height * (1 - CGFloat(min(value / maximum, 1))))
        }
    }
}

/// Device batteries in a row, and the free disk space on the right.
private struct DeviceRow: View {
    let devices: [DeviceBattery]
    let diskFree: Int64?

    var body: some View {
        HStack(spacing: Space.m) {
            if devices.isEmpty {
                Label("No devices with a battery connected", systemImage: "airpodspro")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices.prefix(4)) { device in
                    DeviceChip(device: device)
                }
            }
            Spacer(minLength: 0)
            if let diskFree {
                Label {
                    Text("\(ByteCountFormatter.string(fromByteCount: diskFree, countStyle: .file)) free")
                } icon: {
                    Image(systemName: "internaldrive")
                }
                .font(Typo.micro)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity, minHeight: 40)
        .glassCard()
    }
}

/// "AirPods Pro  L 80%  R 75%  Case 40%", or one level for most devices.
struct DeviceChip: View {
    let device: DeviceBattery

    var body: some View {
        HStack(spacing: Space.xs + 2) {
            Image(systemName: device.symbol).font(Typo.icon(13))
            VStack(alignment: .leading, spacing: 0) {
                Text(device.name).font(Typo.captionStrong).lineLimit(1)
                HStack(spacing: Space.xs + 2) {
                    ForEach(DeviceBattery.Part.allCases, id: \.self) { part in
                        if let level = device.levels[part] {
                            Text("\(label(part))\(level)%")
                                .foregroundStyle(level <= DeviceBatteryLogic.lowLevel ? .red : .secondary)
                        }
                    }
                }
                .font(Typo.number(10, weight: .medium))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func label(_ part: DeviceBattery.Part) -> String {
        switch part {
        case .single: ""
        case .left: String(localized: "battery.left", defaultValue: "L ")
        case .right: String(localized: "battery.right", defaultValue: "R ")
        case .case: String(localized: "battery.case", defaultValue: "Case ")
        }
    }
}
