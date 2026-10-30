import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home
    case nowPlaying
    case weather
    case shelf
    case clipboard
    case search
    case translate
    case system
    case notes
    case notifications
    case mirror

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .nowPlaying: "music.note"
        case .weather: "cloud.sun"
        case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .search: "magnifyingglass"
        case .translate: "character.bubble"
        case .system: "gauge.with.dots.needle.33percent"
        case .notes: "note.text"
        case .notifications: "bell"
        case .mirror: "person.crop.square"
        }
    }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .nowPlaying: String(localized: "Now Playing")
        case .weather: String(localized: "Weather")
        case .shelf: String(localized: "Shelf")
        case .clipboard: String(localized: "Clipboard")
        case .search: String(localized: "Search")
        case .translate: String(localized: "Translate")
        case .system: String(localized: "System")
        case .notes: String(localized: "Notes")
        case .notifications: String(localized: "Notifications")
        case .mirror: String(localized: "Mirror")
        }
    }

    /// Search opens from its button next to Settings (and ⌃⌥K), not from the tab bar.
    var inTabBar: Bool { self != .search }

    /// Tabs you type into; only these let the notch take the keyboard.
    var takesTyping: Bool {
        self == .search || self == .translate || self == .notes
    }
}

/// UI state for one notch. Views read it; the hover controller drives it.
@MainActor
@Observable
final class NotchViewModel {
    let activity: ActivityState
    private(set) var state: NotchState = .closed {
        didSet { if state != oldValue { onStateChange?() } }
    }
    /// Told when the notch opens or closes, however that happened.
    @ObservationIgnored var onStateChange: (() -> Void)?
    var selectedTab: NotchTab = .home
    /// Visible tabs in the user's order.
    private(set) var tabs: [NotchTab] = NotchTab.allCases
    /// The tabs in the tab bar (Search has its own button).
    var barTabs: [NotchTab] { tabs.filter { $0.inTabBar && ($0 != .notifications || showsNotifications) } }
    /// The Notifications tab only shows while notifications come to the notch.
    private(set) var showsNotifications = UserDefaults.standard.bool(forKey: SettingsKey.notificationsEnabled, default: SettingsDefault.notificationsEnabled)
    /// Opens Search ready to type; set by the window controller, which can give the panel
    /// the keyboard.
    @ObservationIgnored var openSearch: (() -> Void)?
    /// Open size from Settings → Appearance → Size.
    private(set) var baseOpenSize: CGSize = SettingsDefault.panelSize.openSize
    /// Compact mode is one short row; some tabs need more room than the chosen size. A
    /// notch outline also grows by its neck, so the content area matches the pill's.
    var openSize: CGSize {
        let size: CGSize
        if tourStep != nil {
            size = NotchLayout.tourSize(base: baseOpenSize)
        } else if settingsPage != nil {
            size = NotchLayout.settingsSize(base: baseOpenSize)
        } else if showsCompact {
            size = NotchLayout.compactSize
        } else {
            size = NotchLayout.size(for: selectedTab, base: baseOpenSize)
        }
        return NotchLayout.openSize(size, outline: outline, notchHeight: notchSize.height)
    }
    /// Settings, shown in place of the tabs; nil while the tabs show.
    private(set) var settingsPage: SettingsPage?
    /// The tour's steps, empty when no tour is showing.
    private(set) var tourSteps: [OnboardingStep] = []
    private(set) var tourIndex = 0
    /// Where finishing the tour is recorded (tests use their own).
    @ObservationIgnored var tourDefaults: UserDefaults = .standard
    var tourStep: OnboardingStep? { tourSteps.indices.contains(tourIndex) ? tourSteps[tourIndex] : nil }
    /// Files dropped on Convert, waiting for a format.
    var convertURLs: [URL] = []
    /// Home is being rearranged.
    var isEditingHome = false
    /// A pop-up menu (a picker, More tabs) is open; it may reach past the notch's edge.
    var isMenuOpen = false
    /// Full or compact (Settings → Appearance).
    private(set) var mode: NotchMode = SettingsDefault.notchMode
    /// Compact mode only: the full notch was asked for, until the notch closes.
    private(set) var isExpanded = false
    /// The compact row shows instead of the tabs. File drags always get the full notch.
    var showsCompact: Bool {
        mode == .compact && !isExpanded && !isDropTargeted && convertURLs.isEmpty && settingsPage == nil && tourStep == nil
    }
    /// The panel has keyboard focus (typing in a tab).
    var isKeyFocused = false
    /// The panel may take keyboard focus: Settings (city search) or a tab you type into.
    var wantsKeyboard: Bool {
        isOpen && (settingsPage != nil || (!showsCompact && selectedTab.takesTyping))
    }
    /// Bumped to put the cursor in the showing tab's text field (after a hotkey).
    private(set) var focusRequest = 0
    private(set) var outline: NotchOutline = .notch
    /// True while the cursor is over the closed notch (for the small hover bump).
    private(set) var isHovering = false
    /// Opened by a hotkey or an action rather than by hovering: stays open until the
    /// cursor has visited the notch and left again.
    private(set) var isHeld = false
    @ObservationIgnored var heldWasHovered = false
    /// Kept open regardless of hover while held, typing or in a menu. A menu only keeps an
    /// open notch open: the menu bar's own menu mustn't open it.
    var isPinnedOpen: Bool { isHeld || isKeyFocused || (isMenuOpen && isOpen) }
    /// Files being dragged over the notch (empty when there's no drag).
    private(set) var dragURLs: [URL] = []
    var isDropTargeted: Bool { !dragURLs.isEmpty }
    /// Size of the hardware (or fallback) notch, in points.
    private(set) var notchSize: CGSize
    private(set) var hasHardwareNotch: Bool
    /// Notch center minus window center. Non-zero only when the window had to be
    /// clamped to stay on screen.
    private(set) var horizontalOffset: CGFloat

    init(activity: ActivityState, metrics: NotchMetrics, panelFrame: CGRect) {
        self.activity = activity
        notchSize = metrics.notchRect.size
        hasHardwareNotch = metrics.hasHardwareNotch
        horizontalOffset = metrics.notchRect.midX - panelFrame.midX
        applySettings()
    }

    var isOpen: Bool { state == .open }

    /// Width of the side indicators while closed (0 when there are none).
    var closedEarWidth: CGFloat { isOpen ? 0 : activity.earWidth }

    func update(metrics: NotchMetrics, panelFrame: CGRect) {
        notchSize = metrics.notchRect.size
        hasHardwareNotch = metrics.hasHardwareNotch
        horizontalOffset = metrics.notchRect.midX - panelFrame.midX
        applySettings()
    }

    /// Re-reads the settings that change layout. Cheap; called when defaults change.
    func applySettings(_ defaults: UserDefaults = .standard) {
        showsNotifications = defaults.bool(forKey: SettingsKey.notificationsEnabled, default: SettingsDefault.notificationsEnabled)
        let tabs = AppearanceLogic.tabs(
            order: defaults.string(forKey: SettingsKey.tabOrder) ?? SettingsDefault.tabOrder,
            hidden: defaults.string(forKey: SettingsKey.hiddenTabs) ?? SettingsDefault.hiddenTabs
        )
        let size = defaults.value(forKey: SettingsKey.panelSize, default: SettingsDefault.panelSize).openSize
        let outline = AppearanceLogic.outline(
            setting: defaults.value(forKey: SettingsKey.notchOutline, default: SettingsDefault.notchOutline),
            hasHardwareNotch: hasHardwareNotch
        )
        let mode = defaults.value(forKey: SettingsKey.notchMode, default: SettingsDefault.notchMode)
        if tabs != self.tabs { self.tabs = tabs }
        if size != baseOpenSize { baseOpenSize = size }
        if outline != self.outline { self.outline = outline }
        if mode != self.mode {
            withAnimation(Motion.open) {
                self.mode = mode
                isExpanded = false
            }
        }
        if !tabs.contains(selectedTab) { selectedTab = tabs[0] }
    }

    /// Opens the notch and keeps it open until the cursor has been on it and left.
    func hold() {
        if !isHeld { heldWasHovered = false }
        isHeld = true
        open()
    }

    func release() {
        isHeld = false
    }

    func requestFocus() {
        focusRequest += 1
    }

    /// Shows Settings in the notch, on `page`.
    func openSettings(_ page: SettingsPage = .general) {
        withAnimation(Motion.open) { settingsPage = page }
        hold()
    }

    func showSettingsPage(_ page: SettingsPage) {
        withAnimation(Motion.tab) { settingsPage = page }
    }

    func closeSettings() {
        guard settingsPage != nil else { return }
        withAnimation(Motion.open) { settingsPage = nil }
    }

    /// Shows the tour in the notch. Like anything held it closes once the cursor has visited and
    /// left, and hovering brings the tour back at the same step.
    func startTour(_ steps: [OnboardingStep] = OnboardingStep.allCases) {
        guard !steps.isEmpty else { return }
        withAnimation(Motion.open) {
            settingsPage = nil
            tourSteps = steps
            tourIndex = 0
        }
        hold()
    }

    func nextTourStep() {
        guard tourIndex + 1 < tourSteps.count else { return endTour() }
        withAnimation(Motion.tab) { tourIndex += 1 }
    }

    func previousTourStep() {
        guard tourIndex > 0 else { return }
        withAnimation(Motion.tab) { tourIndex -= 1 }
    }

    /// Finished or skipped: either way it isn't shown again on launch.
    func endTour() {
        guard !tourSteps.isEmpty else { return }
        OnboardingLogic.markSeen(tourDefaults)
        withAnimation(Motion.open) {
            tourSteps = []
            tourIndex = 0
        }
    }

    func dragChanged(_ urls: [URL]) {
        guard urls != dragURLs else { return }
        withAnimation(Motion.quick) { dragURLs = urls }
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        withAnimation(Motion.hover) { isHovering = hovering }
    }

    /// A click on the closed notch.
    func clickClosed(on side: ClosedNotchSide) {
        guard !isOpen else { return }
        let defaults = UserDefaults.standard
        let click = ClosedNotchLogic.click(
            ears: activity.ears,
            side: side,
            left: defaults.value(forKey: SettingsKey.leftEarClick, default: SettingsDefault.leftEarClick),
            right: defaults.value(forKey: SettingsKey.rightEarClick, default: SettingsDefault.rightEarClick)
        )
        switch click {
        case .activateNotification(let item): activity.live.activate(item)
        case .open, .ear(.open): open()   // click-to-open; also skips the hover delay
        case .ear(.openPlayer): activity.openPlayingApp()
        case .ear(.playPause): activity.player?.perform(.playPause)
        case .ear(.nextTrack): activity.player?.perform(.next)
        case .ear(.keepAwake): activity.toggleKeepAwake()
        }
    }

    /// Switches to `tab` if it's visible (e.g. the shelf when files are dragged in).
    func show(_ tab: NotchTab) {
        if tabs.contains(tab) { selectedTab = tab }
    }

    /// Compact mode: show the full notch (on `tab`, if given) until it closes.
    func expand(to tab: NotchTab? = nil) {
        if let tab { show(tab) }
        guard mode == .compact, !isExpanded else { return }
        withAnimation(Motion.open) { isExpanded = true }
    }

    /// Compact mode: back to the single row.
    func collapse() {
        guard isExpanded else { return }
        withAnimation(Motion.open) { isExpanded = false }
    }

    func open() {
        guard state != .open else { return }
        activity.player?.refreshPosition()
        activity.weather.refreshIfNeeded()
        activity.updates.checkIfDue()
        activity.devices.refreshIfNeeded()
        withAnimation(Motion.open) { state = .open }
    }

    func close() {
        guard state != .closed else { return }
        isHeld = false
        withAnimation(Motion.close) {
            state = .closed
            isExpanded = false
            settingsPage = nil
            convertURLs = []
        }
    }
}
