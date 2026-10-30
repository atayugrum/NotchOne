import SwiftUI

struct MenuContent: View {
    var body: some View {
        Button("Settings…") {
            SettingsOpener.open(page: .general)
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit NotchOne") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
