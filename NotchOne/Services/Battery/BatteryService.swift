import Foundation
import IOKit.ps

enum BatteryReader {
    /// Internal battery state, or nil on Macs without one.
    static func read() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let capacity = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = capacity > 0 ? Int((Double(current) / Double(capacity) * 100).rounded()) : 0

            return BatteryStatus(
                percent: min(100, max(0, percent)),
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false
            )
        }
        return nil
    }
}

/// Listens for IOKit power-source changes (event driven, no polling).
@MainActor
final class BatteryService {
    private let activity: ActivityState
    private var runLoopSource: CFRunLoopSource?
    private var warned: Set<Int> = []

    init(activity: ActivityState) {
        self.activity = activity
    }

    func start() {
        guard runLoopSource == nil else { return }
        refresh()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.refresh() }
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
    }

    private func refresh() {
        guard let current = BatteryReader.read() else { return }
        let result = BatteryPeekLogic.evaluate(previous: activity.battery, current: current, warned: warned)
        warned = result.warned
        activity.battery = current

        let alertsOn = UserDefaults.standard.bool(
            forKey: SettingsKey.batteryAlertsEnabled,
            default: SettingsDefault.batteryAlertsEnabled
        )
        if let peek = result.peek, alertsOn {
            activity.showPeek(peek)
        }
    }
}
