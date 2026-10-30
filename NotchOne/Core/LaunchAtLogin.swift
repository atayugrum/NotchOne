import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when macOS wants the user to approve it in System Settings > Login Items.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// The login item remembers where the app was when it was turned on. After the app
    /// moves (e.g. into /Applications), register again so login starts this copy.
    static func refreshIfMoved(defaults: UserDefaults = .standard) {
        let key = "launchAtLoginPath"
        let path = Bundle.main.bundleURL.path
        guard isEnabled else {
            defaults.removeObject(forKey: key)
            return
        }
        guard defaults.string(forKey: key) != path else { return }
        try? SMAppService.mainApp.unregister()
        try? SMAppService.mainApp.register()
        defaults.set(path, forKey: key)
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
