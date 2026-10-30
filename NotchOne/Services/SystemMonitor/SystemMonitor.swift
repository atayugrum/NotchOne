import Darwin
import Foundation

/// Raw counters read in one go. CPU ticks and network bytes only mean something as the
/// difference between two readings.
struct SystemCounters: Equatable, Sendable {
    var cpuBusy: UInt64
    var cpuTotal: UInt64
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var bytesIn: UInt64
    var bytesOut: UInt64
    var diskFree: Int64?
    var time: Date
}

/// What the System tab shows.
struct SystemSample: Equatable, Sendable {
    /// 0…1
    var cpu: Double
    /// 0…1
    var memory: Double
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    /// Bytes per second.
    var download: Double
    var upload: Double
    var diskFree: Int64?
}

enum SystemMonitorLogic {
    /// Samples kept for the little graphs (one a second).
    static let historyLength = 60

    static func sample(from old: SystemCounters, to new: SystemCounters) -> SystemSample {
        let total = new.cpuTotal &- old.cpuTotal
        let busy = new.cpuBusy &- old.cpuBusy
        let seconds = max(new.time.timeIntervalSince(old.time), 0.001)
        // Counters reset when an interface goes away; a drop is treated as no traffic.
        let down = new.bytesIn >= old.bytesIn ? Double(new.bytesIn - old.bytesIn) / seconds : 0
        let up = new.bytesOut >= old.bytesOut ? Double(new.bytesOut - old.bytesOut) / seconds : 0
        return SystemSample(
            cpu: total > 0 && busy <= total ? Double(busy) / Double(total) : 0,
            memory: new.memoryTotal > 0 ? min(1, Double(new.memoryUsed) / Double(new.memoryTotal)) : 0,
            memoryUsed: new.memoryUsed,
            memoryTotal: new.memoryTotal,
            download: down,
            upload: up,
            diskFree: new.diskFree
        )
    }

    static func append(_ value: Double, to history: [Double]) -> [Double] {
        Array((history + [value]).suffix(historyLength))
    }

    /// "1.2 MB/s", "340 KB/s", "0 KB/s".
    static func rate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // "0 KB/s", not "Zero KB/s".
        formatter.allowsNonnumericFormatting = false
        return "\(formatter.string(fromByteCount: Int64(max(0, bytesPerSecond))))/s"
    }
}

/// Reads the counters with public kernel calls; none of them needs a permission.
enum SystemCounterReader {
    static func read(now: Date = Date()) -> SystemCounters {
        let cpu = cpuTicks()
        let memory = memoryUse()
        let network = networkBytes()
        let disk = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        return SystemCounters(
            cpuBusy: cpu.busy, cpuTotal: cpu.total,
            memoryUsed: memory, memoryTotal: ProcessInfo.processInfo.physicalMemory,
            bytesIn: network.in, bytesOut: network.out,
            diskFree: disk, time: now
        )
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    /// Active, wired and compressed memory: roughly what Activity Monitor calls memory used.
    private static func memoryUse() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(sysconf(_SC_PAGESIZE))
    }

    /// Bytes in and out on every interface except loopback, from the 64-bit counters.
    private static func networkBytes() -> (in: UInt64, out: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return (0, 0) }
        var totalIn: UInt64 = 0, totalOut: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.load(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.load(fromByteOffset: offset, as: if_msghdr2.self)
                    let isLoopback = (message.ifm_flags & IFF_LOOPBACK) != 0
                    if !isLoopback {
                        totalIn += message.ifm_data.ifi_ibytes
                        totalOut += message.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (totalIn, totalOut)
    }
}

/// Samples once a second, but only while something on screen shows it (the System tab or
/// its Home card), so the app still idles at 0% CPU.
@MainActor
@Observable
final class SystemMonitorStore {
    private(set) var current: SystemSample?
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var downloadHistory: [Double] = []
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var last: SystemCounters?

    /// Call when a view that shows the stats appears; `stopWatching` when it goes away.
    func startWatching() {
        watchers += 1
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let counters = await Task.detached(priority: .utility) { SystemCounterReader.read() }.value
                self?.take(counters)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        task?.cancel()
        task = nil
        last = nil
    }

    private func take(_ counters: SystemCounters) {
        defer { last = counters }
        guard let last else { return }
        let sample = SystemMonitorLogic.sample(from: last, to: counters)
        current = sample
        cpuHistory = SystemMonitorLogic.append(sample.cpu, to: cpuHistory)
        memoryHistory = SystemMonitorLogic.append(sample.memory, to: memoryHistory)
        downloadHistory = SystemMonitorLogic.append(sample.download, to: downloadHistory)
    }
}
