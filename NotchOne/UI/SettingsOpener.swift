import Foundation

/// Opens Settings (in the notch) on a page, from anywhere. The window controller sets
/// `handler` when it starts.
@MainActor
enum SettingsOpener {
    static var handler: ((SettingsPage) -> Void)?

    static func open(page: SettingsPage) {
        handler?(page)
    }
}
