import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: ServiceCoordinator?
    private var notchController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests launch the app as a host; don't put a window on screen then.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        #if DEBUG
        if let zip = UserDefaults.standard.string(forKey: "debugUpdateZip"),
           let target = UserDefaults.standard.string(forKey: "debugUpdateTarget") {
            UpdateStore.debugInstall(zip: URL(fileURLWithPath: zip), target: URL(fileURLWithPath: target))
            exit(0)
        }
        #endif
        LaunchAtLogin.refreshIfMoved()
        CommandLineTool.relinkIfStale()

        let services = ServiceCoordinator()
        services.start()
        self.services = services

        let controller = NotchWindowController(activity: services.activity)
        controller.start()
        notchController = controller
        SettingsOpener.handler = { [weak controller] page in controller?.openSettings(page) }

        if Translator.isSupported {
            HotKeyCenter.shared.register(.translate) { [weak controller] in controller?.translateSelection() }
        }
        HotKeyCenter.shared.register(.palette) { [weak controller] in controller?.toggleSearch() }
    }

    /// `notchone://` URLs (Shortcuts, scripts, hooks).
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { services?.input.receive(url: $0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregisterAll()
        notchController?.stop()
        services?.stop()
    }
}
