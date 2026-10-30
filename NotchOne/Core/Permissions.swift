import ApplicationServices
import CoreBluetooth
import Foundation

/// Permissions macOS asks for the first time a feature touches them. NotchOne never touches
/// them in the background until you've pressed that permission's button (in the tour or in
/// Settings → Privacy), so nothing asks on launch. Location and Camera already ask only from
/// their own buttons, and the Focus moon only once you turn it on.
enum PermissionKind: String, CaseIterable, Sendable {
    /// Volume and brightness keys, translating the selection.
    case accessibility
    /// Headphone and other Bluetooth device alerts.
    case bluetooth
    /// Reading and controlling Music and Spotify.
    case automation
    /// Watching Desktop and Downloads for new screenshots and downloads.
    case folders
}

enum PermissionGate {
    static let key = "permissionsRequested"

    static func requested(_ defaults: UserDefaults = .standard) -> Set<PermissionKind> {
        Set((defaults.string(forKey: key) ?? "").split(separator: ",").compactMap { PermissionKind(rawValue: String($0)) })
    }

    /// You pressed the button: the feature may now use it, which is when macOS asks.
    static func markRequested(_ kind: PermissionKind, _ defaults: UserDefaults = .standard) {
        var kinds = requested(defaults)
        guard kinds.insert(kind).inserted else { return }
        if defaults == .standard { SystemPromptWatcher.expectPrompt() }
        defaults.set(kinds.map(\.rawValue).sorted().joined(separator: ","), forKey: key)
    }

    /// The feature may use the permission: you asked for it, or macOS already allows it
    /// (checked without showing a prompt).
    static func allows(_ kind: PermissionKind, _ defaults: UserDefaults = .standard) -> Bool {
        requested(defaults).contains(kind) || isGranted(kind)
    }

    /// Whether macOS already allows it, without asking. Folders can't be checked without
    /// touching them, so they count as granted only once requested.
    static func isGranted(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility: AXIsProcessTrusted()
        case .bluetooth: CBManager.authorization == .allowedAlways
        case .automation: PlayerApp.scriptable.contains { automationStatus(for: $0.bundleID, ask: false) == noErr }
        case .folders: false
        }
    }

    /// Asks macOS whether NotchOne may send Apple Events to the app. With `ask`, macOS shows
    /// its prompt if needed; the app has to be running for that.
    nonisolated static func automationStatus(for bundleID: String, ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let id = Array(bundleID.utf8)
        guard AECreateDesc(typeApplicationBundleID, id, id.count, &target) == noErr else { return OSStatus(procNotFound) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
    }
}
