import AppKit
import SwiftUI

/// Owns the notch panel: picks the screen, sizes the window, and rebuilds it
/// when displays change (lid open/close, monitor plugged in, resolution change).
@MainActor
final class NotchWindowController {
    private let activity: ActivityState
    private var panel: NotchPanel?
    private var dropCatcher: DropCatcherPanel?
    private var model: NotchViewModel?
    private var hover: HoverController?
    private var swipes: SwipeController?
    private var promptWatcher: SystemPromptWatcher?
    private var indicatorWatcher: StatusIndicatorWatcher?
    private var menuWatcher: MenuBarWatcher?
    private var metrics: NotchMetrics?
    private var panelFrame: CGRect = .zero
    private var observers: [NSObjectProtocol] = []
    private var lastShowWithoutNotch: Bool?

    init(activity: ActivityState) {
        self.activity = activity
    }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        })
        // A pop-up menu can reach past the notch; leaving the notch for it isn't leaving.
        for (name, isOpen) in [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model?.isMenuOpen = isOpen
                    if !isOpen { self?.hover?.evaluate() }
                }
            })
        }
        lastShowWithoutNotch = Self.showWithoutNotch
        rebuild()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        tearDown()
    }

    // MARK: - Private

    private static var showWithoutNotch: Bool {
        UserDefaults.standard.bool(
            forKey: SettingsKey.showOnDisplaysWithoutNotch,
            default: SettingsDefault.showOnDisplaysWithoutNotch
        )
    }

    /// Screenshots and screen sharing leave the notch out, for apps that honour this.
    private func applyCaptureVisibility() {
        let hidden = UserDefaults.standard.bool(forKey: SettingsKey.hideFromCapture, default: SettingsDefault.hideFromCapture)
        panel?.sharingType = hidden ? .none : .readOnly
    }

    private func settingsChanged() {
        model?.applySettings()
        applyCaptureVisibility()
        let value = Self.showWithoutNotch
        guard value != lastShowWithoutNotch else { return }
        lastShowWithoutNotch = value
        rebuild()
    }

    /// Built-in notched display first; otherwise the primary display if allowed.
    private func targetScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: \.hasHardwareNotch) {
            return notched
        }
        return Self.showWithoutNotch ? NSScreen.screens.first : nil
    }

    private func rebuild() {
        guard let screen = targetScreen() else {
            tearDown()
            return
        }

        let metrics = screen.notchMetrics
        let frame = ScreenGeometry.panelFrame(notchRect: metrics.notchRect, screenFrame: screen.frame)
        self.metrics = metrics
        self.panelFrame = frame

        if let panel, let model {
            model.update(metrics: metrics, panelFrame: frame)
            panel.setFrame(frame, display: true)
        } else {
            create(metrics: metrics, frame: frame)
        }
        dropCatcher?.setFrame(metrics.notchRect, display: false)
        panel?.orderFrontRegardless()
        dropCatcher?.orderFrontRegardless()
        hover?.evaluate()
    }

    private func create(metrics: NotchMetrics, frame: CGRect) {
        let model = NotchViewModel(activity: activity, metrics: metrics, panelFrame: frame)
        let panel = NotchPanel(contentRect: frame)

        let hosting = NotchHostingView(rootView: NotchRootView(model: model))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        hosting.onDragChange = { [weak model] urls in model?.dragChanged(urls) }
        panel.contentView = hosting

        let hover = HoverController(
            model: model,
            hoverRect: { [weak self] state in
                guard let self, let metrics = self.metrics else { return .null }
                return ScreenGeometry.hoverRect(
                    notchRect: metrics.notchRect,
                    isOpen: state == .open,
                    panelFrame: self.panelFrame,
                    earWidth: self.model?.closedEarWidth ?? 0,
                    earDrop: self.activity.earDrop,
                    openSize: self.model?.openSize ?? NotchLayout.openSize
                )
            },
            notchRect: { [weak self] in self?.metrics?.notchRect },
            onInsideChange: { [weak self, weak panel, weak model] inside in
                // Let clicks through everywhere except the notch itself.
                panel?.ignoresMouseEvents = !inside
                model?.setHovering(inside)
                self?.promptWatcher?.refresh()
            }
        )

        let catcher = DropCatcherPanel(frame: metrics.notchRect)
        catcher.onDragEnter = { [weak self] urls in
            guard let self, let model = self.model,
                  UserDefaults.standard.bool(forKey: SettingsKey.openOnFileDrag, default: SettingsDefault.openOnFileDrag)
            else { return }
            model.dragChanged(urls)
            model.open()
            // Let the drag continue onto the open notch's drop area.
            self.panel?.ignoresMouseEvents = false
            self.hover?.evaluate()
        }
        catcher.onClick = { [weak model] in model?.clickClosed(on: .center) }
        catcher.onDrop = { [weak self] urls in
            guard let self, let model = self.model else { return }
            self.activity.shelf.add(urls)
            model.show(.shelf)
        }

        self.model = model
        self.panel = panel
        applyCaptureVisibility()
        self.hover = hover
        self.dropCatcher = catcher
        hover.start()

        panel.onResignKey = { [weak model] in model?.isKeyFocused = false }
        panel.onBecomeKey = { [weak model] in model?.isKeyFocused = true }

        let swipes = SwipeController(
            model: model,
            windows: { [weak self] in [self?.panel, self?.dropCatcher].compactMap { $0 } },
            headerBottom: { [weak self] in
                guard let self, let model = self.model else { return .greatestFiniteMagnitude }
                let top = NotchLayout.contentTopInset(outline: model.outline, notchHeight: model.notchSize.height)
                    + (model.outline == .pill ? NotchLayout.pillGap : 0)
                return self.panelFrame.maxY - top - 34
            }
        )
        swipes.start()
        self.swipes = swipes
        model.openSearch = { [weak self] in self?.focus(.search) }
        let promptWatcher = SystemPromptWatcher(
            windows: { [weak self] in [self?.panel].compactMap { $0 } },
            notchOpen: { [weak self] in self?.model?.isOpen == true }
        )
        promptWatcher.start()
        model.onStateChange = { [weak self] in
            if self?.model?.isOpen == true { self?.promptWatcher?.notchOpened() }
            self?.promptWatcher?.refresh()
        }
        self.promptWatcher = promptWatcher
        let indicatorWatcher = StatusIndicatorWatcher(
            activity: activity,
            panel: { [weak self] in self?.panel },
            notchRect: { [weak self] in self?.metrics?.notchRect }
        )
        indicatorWatcher.start()
        self.indicatorWatcher = indicatorWatcher
        let menuWatcher = MenuBarWatcher(activity: activity, notchRect: { [weak self] in self?.metrics?.notchRect })
        menuWatcher.start()
        self.menuWatcher = menuWatcher
        observeKeyboard()

        // First launch: the tour. After an update: only the steps added since.
        let steps = OnboardingLogic.pendingSteps()
        if !steps.isEmpty {
            Task { @MainActor [weak self] in
                // Let the panel settle on screen first.
                try? await Task.sleep(for: .milliseconds(800))
                self?.startTour(steps)
            }
        }

        #if DEBUG
        // `-debugDragPreview <file>` shows the drop zones as if that file were being dragged.
        // `-debugTab <name>` starts on that tab (with `-debugPinOpen YES`, for screenshots).
        if let name = UserDefaults.standard.string(forKey: "debugTab"), let tab = NotchTab(rawValue: name) {
            model.show(tab)
        }
        // `-debugNotifications YES` fills the Notifications tab with samples, for screenshots.
        if UserDefaults.standard.bool(forKey: "debugNotifications") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                let samples = [
                    ("c", "Calendar", "Team sync", "Starts in 10 minutes"),
                    ("b", "Reminders", "Call the dentist", "Today at 16:00"),
                    ("a", "Mail", "Ada: Lunch tomorrow?", "There's a new place near the office. One o'clock works for me."),
                ]
                for (id, app, title, body) in samples {
                    self?.activity.live.show(NotificationBanner(id: id, app: app, title: title, body: body), appPID: nil, appBundleID: nil)
                }
            }
        }
        // `-debugSettings <page>` opens Settings in the notch on that page.
        if let name = UserDefaults.standard.string(forKey: "debugSettings"), let page = SettingsPage(rawValue: name) {
            model.openSettings(page)
        }
        // `-debugExpectPrompt YES` acts as if an Allow button was just pressed (watches for a system prompt).
        if UserDefaults.standard.bool(forKey: "debugExpectPrompt") { SystemPromptWatcher.expectPrompt() }
        // `-debugAskLocation YES` presses "Use my location" (shows the system prompt if not asked yet).
        if UserDefaults.standard.bool(forKey: "debugAskLocation") { activity.weather.useCurrentLocation() }
        // `-debugTour <step>` shows the tour from that step.
        if let name = UserDefaults.standard.string(forKey: "debugTour"), let step = OnboardingStep(rawValue: name) {
            model.startTour(Array(OnboardingStep.allCases.drop { $0 != step }))
        }
        // `-debugPeek <name>` shows a short event under the closed notch.
        switch UserDefaults.standard.string(forKey: "debugPeek") {
        case "airpods": activity.debugShowAirPods()
        case "charging": activity.showPeek(.power(pluggedIn: true, percent: 87), seconds: 30)
        case "low": activity.showPeek(.lowBattery(percent: 9), seconds: 30)
        case "focus": activity.showPeek(.focus(on: true), seconds: 30)
        default: break
        }
        // `-debugEditHome YES` shows Home in edit mode.
        if UserDefaults.standard.bool(forKey: "debugEditHome") { model.isEditingHome = true }
        // `-debugTranslate "<text>"` translates it in the Translate tab.
        if let text = UserDefaults.standard.string(forKey: "debugTranslate") {
            model.show(.translate)
            activity.translate.translate(text)
        }
        // `-debugConvert <file>` asks for a format as if that file was dropped on Convert.
        if let path = UserDefaults.standard.string(forKey: "debugConvert") {
            model.convertURLs = [URL(fileURLWithPath: path)]
        }
        if let path = UserDefaults.standard.string(forKey: "debugDragPreview") {
            model.dragChanged(path.split(separator: ",").map { URL(fileURLWithPath: String($0)) })
        }
        #endif
    }

    // MARK: - Hotkeys

    /// ⌃⌥T: translate the selection in the frontmost app, in the Translate tab.
    func translateSelection() {
        guard let model else { return }
        let translator = activity.translate
        model.expand(to: .translate)
        model.hold()
        translator.showReading()
        Task {
            // Let the user let go of ⌃⌥ before a ⌘C is simulated.
            try? await Task.sleep(for: .milliseconds(120))
            guard let text = await SelectionReader.selectedText(clipboard: activity.clipboard), !text.isEmpty else {
                translator.showFailure(String(localized: "Select some text first, then press \(HotKey.translate.display)."))
                return
            }
            translator.translate(text)
        }
    }

    /// ⌃⌥K: open the Search tab ready to type, or close it again.
    func toggleSearch() {
        guard let model else { return }
        if model.isOpen, model.selectedTab == .search, model.isKeyFocused {
            model.close()
        } else {
            focus(.search)
        }
    }

    /// Settings… in the menu bar, or a "Choose a city…" style link: Settings in the notch.
    func openSettings(_ page: SettingsPage) {
        guard let model, let panel else { return }
        model.openSettings(page)
        panel.ignoresMouseEvents = false
        hover?.evaluate()
    }

    /// The tour in the notch, clickable straight away.
    func startTour(_ steps: [OnboardingStep] = OnboardingStep.allCases) {
        guard let model, let panel else { return }
        model.startTour(steps)
        panel.ignoresMouseEvents = false
        hover?.evaluate()
    }

    /// Opens `tab` and gives the panel the keyboard, with the cursor in its text field.
    private func focus(_ tab: NotchTab) {
        guard let model, let panel else { return }
        model.expand(to: tab)
        model.hold()
        applyKeyboard()
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        model.requestFocus()
        hover?.evaluate()
    }

    /// The panel may take the keyboard only while a tab you type into is showing.
    private func observeKeyboard() {
        guard let model else { return }
        withObservationTracking {
            _ = model.wantsKeyboard
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyKeyboard()
                self?.observeKeyboard()
            }
        }
    }

    private func applyKeyboard() {
        guard let model, let panel else { return }
        let wants = model.wantsKeyboard
        guard wants != panel.allowsKey else { return }
        panel.allowsKey = wants
        if !wants, panel.isKeyWindow {
            panel.resignKey()
            panel.orderFrontRegardless()
        }
    }

    private func tearDown() {
        hover?.stop()
        swipes?.stop()
        swipes = nil
        promptWatcher?.stop()
        promptWatcher = nil
        indicatorWatcher?.stop()
        indicatorWatcher = nil
        menuWatcher?.stop()
        menuWatcher = nil
        panel?.orderOut(nil)
        panel?.close()
        dropCatcher?.orderOut(nil)
        dropCatcher?.close()
        dropCatcher = nil
        hover = nil
        panel = nil
        model = nil
        metrics = nil
    }
}
