import SwiftUI

@main
struct NotchOneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            // The N1 mark, as a template image so macOS tints it for the menu bar.
            Image("MenuBarIcon").accessibilityLabel("NotchOne")
        }
    }
}
