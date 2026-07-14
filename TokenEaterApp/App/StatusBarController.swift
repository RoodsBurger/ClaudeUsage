import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject {
    /// Floor for the non-onboarding dashboard window -> wide enough for
    /// `SidebarNav`'s minimum column width (190pt) plus a usable detail pane.
    /// Shared by `showDashboard` (`minSize`/`contentMinSize`) and
    /// `windowWillResize`'s hard clamp so both stay in sync.
    static let dashboardMinSize = NSSize(width: 760, height: 480)

    private var statusItem: NSStatusItem
    /// Borderless, non-activating panel that replaces `NSPopover` for the
    /// quick-glance dropdown - no arrow, RaiDrive-style. Backed by an
    /// `NSVisualEffectView` (see `makePopoverPanel`) so it keeps the same
    /// native translucent material `NSPopover` gave it for free. Rebuilt
    /// lazily and reused across opens; its SwiftUI content is torn down and
    /// recreated on every open/close (see `installPopoverContent`/
    /// `dismissPopover`) so it always starts from fresh state, matching the
    /// old `NSPopover`'s own contentViewController lifecycle.
    private var popoverPanel: NSPanel?
    private var popoverHostingController: NSHostingController<AnyView>?
    private var dashboardWindow: NSWindow?
    private var eventMonitor: Any?
    private var localKeyMonitor: Any?
    private var appDeactivateObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?
    /// Re-renders the status item text/dot color when the menu bar's actual
    /// background (translucent - shows the desktop through it) flips between
    /// dark and light, independent of any periodic tick.
    private var appearanceObservation: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()
    private var countdownCancellable: AnyCancellable?
    private var rotateCancellable: AnyCancellable?
    /// Index into the visible pins for `.rotate` display mode. Renderer wraps
    /// it modulo the visible count, so any monotonically-increasing value works.
    private var rotateIndex = 0

    private let usageStore: UsageStore
    private let settingsStore: SettingsStore
    private let vendorStatusStore: VendorStatusStore
    private let tokenFileMonitor: TokenFileMonitorProtocol

    init(
        usageStore: UsageStore,
        settingsStore: SettingsStore,
        vendorStatusStore: VendorStatusStore,
        tokenFileMonitor: TokenFileMonitorProtocol = TokenFileMonitor()
    ) {
        self.usageStore = usageStore
        self.settingsStore = settingsStore
        self.vendorStatusStore = vendorStatusStore
        self.tokenFileMonitor = tokenFileMonitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem.isVisible = settingsStore.showMenuBar

        super.init()

        setupStatusItem()
        observeStoreChanges()
        observeDashboardRequest()

        if settingsStore.hasCompletedOnboarding {
            bootstrapRefresh()
        } else {
            observeOnboardingForRefresh()
        }

        // Auto-open the dashboard at launch unless the user opted into a
        // background (menu-bar-only) launch. Onboarding ALWAYS opens: the
        // window hosts the onboarding flow and, being an LSUIElement app with
        // no Dock icon, suppressing it on a fresh install would strand the user
        // with no reachable UI (#198). The window stays reachable from the menu
        // bar's right-click "Open" item afterwards.
        if !settingsStore.hasCompletedOnboarding || !settingsStore.launchInBackground {
            DispatchQueue.main.async { [weak self] in
                self?.showDashboard()
            }
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        button.action = #selector(statusBarClicked)
        button.target = self
        // Accept both primary and secondary clicks so we can route right-click
        // (and trackpad two-finger tap - macOS surfaces those as rightMouseUp)
        // to a contextual menu while keeping left-click tied to the popover.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // The menu bar is translucent - its actual on-screen background can
        // be dark or light independent of the system's overall Light/Dark
        // Mode setting (it shows the desktop picture through it). Watch the
        // button's own effective appearance (not `NSApp`'s) and re-render
        // immediately when it flips, on top of the periodic re-read every
        // `updateMenuBarIcon()` tick already does.
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateMenuBarIcon() }
        }
        updateMenuBarIcon()
    }

    /// Whether the status item currently renders on a dark menu bar
    /// background - drives `MenuBarRenderer`'s adaptive text/dot color.
    /// Falls back to `true` (dark) if the button isn't available yet.
    private var menuBarIsDark: Bool {
        guard let button = statusItem.button else { return true }
        return button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Borderless, `.nonactivatingPanel` panel anchored under the status item.
    /// No arrow (unlike `NSPopover`), no forced appearance - the
    /// `NSVisualEffectView` backing follows the system material, so it tracks
    /// light/dark automatically instead of always rendering dark. Dismissal is
    /// fully manual (see `startPopoverDismissMonitors`): click-outside,
    /// Escape, app-deactivation (Cmd-Tab) and Space changes all close it, the
    /// same set `NSPopover`'s `.applicationDefined` behavior gave us before -
    /// still needed since a floating panel has no built-in transient dismissal.
    private func makePopoverPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Native vibrancy: NSPopover rendered this automatically; a borderless
        // panel needs its own NSVisualEffectView, masked to rounded corners.
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        panel.contentView = effectView

        return panel
    }

    /// (Re)builds the panel's SwiftUI content from scratch - same lifecycle
    /// `NSPopover` had (a fresh `contentViewController` on every open), so the
    /// popover never carries stale view state between opens.
    private func installPopoverContent() {
        let panel = popoverPanel ?? makePopoverPanel()
        popoverPanel = panel
        guard let effectView = panel.contentView else { return }

        popoverHostingController?.view.removeFromSuperview()

        let popoverView = MenuBarPopoverView()
            .environmentObject(usageStore)
            .environmentObject(settingsStore)
            .environmentObject(vendorStatusStore)
        let hosting = NSHostingController(rootView: AnyView(popoverView))
        let fitSize = hosting.view.fittingSize
        hosting.view.frame = NSRect(origin: .zero, size: fitSize)
        hosting.view.autoresizingMask = [.width, .height]
        effectView.addSubview(hosting.view)
        popoverHostingController = hosting
    }

    /// Re-sizes the already-open panel when its SwiftUI content's ideal size
    /// changes (e.g. a live refresh reveals/hides a metric row), keeping the
    /// top-right corner anchored under the status item. Cheap no-op otherwise -
    /// hooked into the same debounced store-change sink `updateMenuBarIcon()`
    /// already uses (see `observeStoreChanges`).
    private func resizePopoverPanelIfNeeded() {
        guard let panel = popoverPanel, panel.isVisible, let hosting = popoverHostingController else { return }
        hosting.view.layoutSubtreeIfNeeded()
        let fitSize = hosting.view.fittingSize
        let size = NSSize(width: max(fitSize.width, 340), height: max(fitSize.height, 1))
        guard abs(size.height - panel.frame.height) > 0.5 || abs(size.width - panel.frame.width) > 0.5 else { return }
        let topRight = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: topRight.x - size.width, y: topRight.y - size.height))
    }

    private func observeStoreChanges() {
        Publishers.MergeMany(
            usageStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            vendorStatusStore.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateMenuBarIcon()
            self?.updateCountdownTimer()
            self?.resizePopoverPanelIfNeeded()
        }
        .store(in: &cancellables)

        Timer.publish(every: 60, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let needsCountdown = self.settingsStore.pinnedMetrics.contains(.sessionReset)
                    || self.settingsStore.display.menuBarConfig.pinned.contains(where: { $0.showCountdown })
                guard needsCountdown else { return }
                self.usageStore.refreshResetCountdown()
            }
            .store(in: &cancellables)

        // Rotate timer: only runs while displayMode == .rotate, restarts
        // whenever the mode or cadence changes so a cadence edit takes effect
        // immediately instead of waiting out the old interval.
        settingsStore.display.$menuBarConfig
            .map { ($0.displayMode, $0.rotateSeconds) }
            .removeDuplicates(by: ==)
            .sink { [weak self] _ in self?.updateRotateTimer() }
            .store(in: &cancellables)

        settingsStore.pacing.$margin
            .removeDuplicates()
            .sink { [weak self] newMargin in
                self?.usageStore.pacingMargin = newMargin
                self?.usageStore.recalculatePacing()
            }
            .store(in: &cancellables)

        // Any workweek-schedule change (toggle / days / hours) re-bases the
        // expected pace. Deferred to the main run loop so the schedule is read
        // AFTER @Published's willSet has committed every new value, then
        // recompute and reload the widget (which reads the schedule from the
        // shared file the settingsStore wrote in its didSet).
        Publishers.MergeMany(
            settingsStore.pacing.$workweekEnabled.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.pacing.$activeDays.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.pacing.$hoursEnabled.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.pacing.$startHour.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.pacing.$endHour.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.usageStore.pacingSchedule = self.settingsStore.pacingSchedule
            self.usageStore.recalculatePacing()
        }
        .store(in: &cancellables)

        settingsStore.$refreshInterval
            .removeDuplicates()
            .sink { [weak self] newInterval in
                self?.usageStore.refreshIntervalSeconds = TimeInterval(newInterval)
            }
            .store(in: &cancellables)

        settingsStore.$statusPollInterval
            .removeDuplicates()
            .sink { [weak self] newInterval in
                self?.vendorStatusStore.healthyPollInterval = TimeInterval(newInterval)
            }
            .store(in: &cancellables)

        settingsStore.$outageMonitoringEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.vendorStatusStore.start() }
                else { self.vendorStatusStore.stop() }
            }
            .store(in: &cancellables)

        settingsStore.display.$showMenuBar
            .removeDuplicates()
            .sink { [weak self] visible in
                self?.statusItem.isVisible = visible
            }
            .store(in: &cancellables)
    }

    private func bootstrapRefresh() {
        usageStore.proxyConfig = settingsStore.proxyConfig
        usageStore.pacingMargin = settingsStore.pacingMargin
        usageStore.pacingSchedule = settingsStore.pacingSchedule
        usageStore.refreshIntervalSeconds = TimeInterval(settingsStore.refreshInterval)
        usageStore.notifTogglesProvider = { [weak self] in self?.makeNotificationToggles() }
        vendorStatusStore.notifTogglesProvider = { [weak self] in self?.makeNotificationToggles() }
        vendorStatusStore.healthyPollInterval = TimeInterval(settingsStore.statusPollInterval)
        usageStore.reloadConfig(thresholds: settingsStore.thresholds)
        usageStore.startAutoRefresh(thresholds: settingsStore.thresholds)

        // Monitor token files (credentials + config.json) for changes
        tokenFileMonitor.startMonitoring()
        tokenFileMonitor.tokenChanged
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.usageStore.handleTokenChange()
                Task { await self.usageStore.refresh(force: true) }
            }
            .store(in: &cancellables)

        // Refresh after wake from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.usageStore.refreshIfStale()
            }
        }

        if settingsStore.outageMonitoringEnabled {
            vendorStatusStore.start()
        }
    }

    /// Single source of truth for the notification-toggle bundle, shared by the
    /// usage store and the vendor-status store so they always agree.
    private func makeNotificationToggles() -> NotificationToggles {
        NotificationToggles(
            masterEnabled: settingsStore.notificationsEnabled,
            trackFiveHour: settingsStore.notifTrackFiveHour,
            trackWeekly: settingsStore.notifTrackWeekly,
            trackSonnet: settingsStore.notifTrackSonnet,
            trackDesign: settingsStore.notifTrackDesign,
            trackFable: settingsStore.notifTrackFable,
            sendRecovery: settingsStore.notifSendRecovery,
            pacingHot: settingsStore.notifPacingHot,
            pacingWarning: settingsStore.notifPacingWarning,
            resetReminderSession: settingsStore.notifResetReminderSession,
            resetReminderWeekly: settingsStore.notifResetReminderWeekly,
            resetReminderSessionOffsetMinutes: settingsStore.notifResetReminderSessionOffset,
            resetReminderWeeklyOffsetMinutes: settingsStore.notifResetReminderWeeklyOffset,
            extraCredits: settingsStore.notifExtraCredits,
            tokenExpired: settingsStore.notifTokenExpired,
            smartColorEnabled: settingsStore.smartColorEnabled,
            smartColorProfile: settingsStore.smartColorProfile,
            pacingMargin: Double(settingsStore.pacingMargin),
            thresholds: settingsStore.thresholds,
            vendorDegraded: settingsStore.notifVendorDegraded,
            vendorRestored: settingsStore.notifVendorRestored
        )
    }

    private func observeOnboardingForRefresh() {
        settingsStore.$hasCompletedOnboarding
            .removeDuplicates()
            .filter { $0 }
            .first()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.bootstrapRefresh()
            }
            .store(in: &cancellables)
    }

    private func observeDashboardRequest() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDashboardRequest(_:)),
            name: .openDashboard,
            object: nil
        )
    }

    @objc private func handleDashboardRequest(_ notification: Notification) {
        showDashboard()

        // Re-post as-is once validated -> `NavigationTarget.parse` also
        // gates the payload MainAppView's own `.navigateToSection` listener
        // will parse, so an unrecognised section never reaches the sidebar.
        if let section = notification.userInfo?["section"] as? String,
           NavigationTarget.parse(section) != nil {
            NotificationCenter.default.post(name: .navigateToSection, object: nil, userInfo: ["section": section])
        }
    }

    // MARK: - Menu Bar Icon

    private func updateMenuBarIcon() {
        let image = MenuBarRenderer.render(MenuBarRenderer.RenderData(
            menuBarConfig: settingsStore.display.menuBarConfig,
            rotateIndex: rotateIndex,
            hasConfig: usageStore.hasConfig,
            hasError: usageStore.hasError,
            thresholds: settingsStore.thresholds,
            smartColorEnabled: settingsStore.smartColorEnabled,
            smartColorProfile: settingsStore.smartColorProfile,
            pacingMargin: Double(settingsStore.pacingMargin),
            fiveHourPct: usageStore.fiveHourPct,
            sevenDayPct: usageStore.sevenDayPct,
            sonnetPct: usageStore.sonnetPct,
            designPct: usageStore.designPct,
            fablePct: usageStore.fablePct,
            extraCreditsPct: usageStore.extraCreditsPct,
            hasFiveHourBucket: usageStore.lastUsage?.fiveHour != nil,
            hasWeeklyPacing: usageStore.pacingResult != nil,
            hasSessionPacing: usageStore.fiveHourPacing != nil,
            hasDesign: usageStore.hasDesign,
            hasFable: usageStore.hasFable,
            hasExtraCredits: usageStore.hasExtraCredits,
            fiveHourResetDate: usageStore.lastUsage?.fiveHour?.resetsAtDate,
            sevenDayResetDate: usageStore.lastUsage?.sevenDay?.resetsAtDate,
            sonnetResetDate: usageStore.lastUsage?.sevenDaySonnet?.resetsAtDate,
            designResetDate: usageStore.lastUsage?.sevenDayDesign?.resetsAtDate,
            fableResetDate: usageStore.lastUsage?.sevenDayFable?.resetsAtDate,
            resetDisplayFormat: settingsStore.resetDisplayFormat,
            fiveHourReset: usageStore.fiveHourReset,
            sevenDayReset: usageStore.sevenDayReset,
            sonnetReset: usageStore.sonnetReset,
            designReset: usageStore.designReset,
            fableReset: usageStore.fableReset,
            fiveHourResetAbsolute: usageStore.fiveHourResetAbsolute,
            sevenDayResetAbsolute: usageStore.sevenDayResetAbsolute,
            sonnetResetAbsolute: usageStore.sonnetResetAbsolute,
            designResetAbsolute: usageStore.designResetAbsolute,
            fableResetAbsolute: usageStore.fableResetAbsolute,
            sessionPacingDelta: Int(usageStore.fiveHourPacing?.delta ?? 0),
            sessionPacingZone: usageStore.fiveHourPacing?.zone ?? .onTrack,
            weeklyPacingDelta: Int(usageStore.pacingResult?.delta ?? 0),
            weeklyPacingZone: usageStore.pacingResult?.zone ?? .onTrack,
            sessionPacingDisplayMode: settingsStore.sessionPacingDisplayMode,
            weeklyPacingDisplayMode: settingsStore.weeklyPacingDisplayMode,
            extraCreditsUsedMinorUnits: usageStore.extraUsage?.usedCredits ?? 0,
            extraCreditsLimitMinorUnits: usageStore.extraUsage?.monthlyLimit ?? 0,
            extraCreditsCurrency: usageStore.extraUsage?.currency ?? "USD",
            outageActive: settingsStore.statusShowMenuBarBadge && vendorStatusStore.isDegraded,
            outageHealth: vendorStatusStore.worstHealth,
            nextPollSeconds: vendorStatusStore.nextPollDate.map { max(0, Int(ceil($0.timeIntervalSinceNow))) },
            menuBarIsDark: menuBarIsDark
        ))
        statusItem.button?.image = image
    }

    /// Starts/stops the rotate timer to match `displayMode`/`rotateSeconds`.
    /// Always rebuilt (never just left running) so a cadence edit takes
    /// effect on the next tick instead of finishing out the old interval.
    private func updateRotateTimer() {
        rotateCancellable?.cancel()
        rotateCancellable = nil

        let config = settingsStore.display.menuBarConfig
        guard config.displayMode == .rotate else { return }

        let interval = TimeInterval(max(1, config.rotateSeconds))
        rotateCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.rotateIndex += 1
                self.updateMenuBarIcon()
            }
    }

    /// Run a 1-second redraw ONLY while an outage badge is visible, so the
    /// menu-bar countdown ticks without waking the CPU every second otherwise.
    private func updateCountdownTimer() {
        let badgeCountdown = settingsStore.statusShowMenuBarBadge && vendorStatusStore.isDegraded
        let pinCountdown = (settingsStore.pinnedMetrics.contains(.serviceStatus)
            || settingsStore.display.menuBarConfig.pinned.contains(where: { $0.id == .serviceStatus }))
            && vendorStatusStore.worstHealth == .down
        let active = badgeCountdown || pinCountdown
        if active, countdownCancellable == nil {
            countdownCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.updateMenuBarIcon() }
        } else if !active {
            countdownCancellable?.cancel()
            countdownCancellable = nil
        }
    }

    // MARK: - Click handling

    @objc private func statusBarClicked() {
        // Right-click or control-click routes to the contextual menu so users
        // get quick access to the most common actions (refresh, settings
        // shortcuts, quit) without opening the popover.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            showContextMenu()
            return
        }
        togglePopover()
    }

    // MARK: - Context menu (right-click)

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = buildContextMenu()
        // Temporarily attach + popUp + detach so the menu appears anchored
        // under the status item button without hijacking left-click.
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Actions
        let refresh = NSMenuItem(
            title: String(localized: "contextmenu.refresh"),
            action: #selector(contextRefresh),
            keyEquivalent: "r"
        )
        refresh.target = self
        refresh.isEnabled = !usageStore.isLoading
        menu.addItem(refresh)

        let openDashboard = NSMenuItem(
            title: String(localized: "contextmenu.open"),
            action: #selector(contextOpenDashboard),
            keyEquivalent: ""
        )
        openDashboard.target = self
        menu.addItem(openDashboard)

        menu.addItem(.separator())

        // Settings submenu (direct section shortcuts)
        let settingsItem = NSMenuItem(
            title: String(localized: "contextmenu.settings"),
            action: nil,
            keyEquivalent: ""
        )
        let settingsSub = NSMenu()
        for section in SettingsSection.allCases {
            let item = NSMenuItem(
                title: section.label,
                action: #selector(contextOpenSection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = "settings.\(section.rawValue)"
            settingsSub.addItem(item)
        }
        settingsItem.submenu = settingsSub
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "menubar.quit"),
            action: #selector(contextQuit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func contextRefresh() {
        Task { await usageStore.refresh(force: true) }
    }

    @objc private func contextOpenDashboard() {
        showDashboard()
    }

    @objc private func contextOpenSection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        showDashboard()
        NotificationCenter.default.post(
            name: .navigateToSection,
            object: nil,
            userInfo: ["section": raw]
        )
    }

    @objc private func contextQuit() {
        NSApp.terminate(nil)
    }

    private func togglePopover() {
        if let panel = popoverPanel, panel.isVisible {
            dismissPopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        installPopoverContent()
        guard let panel = popoverPanel, let hosting = popoverHostingController else { return }

        // Fullscreen fix: a menu-bar panel opened over a fullscreen-app Space
        // is created on the default Space, so the cursor over the visible
        // panel would read as "outside" and the click-outside monitor below
        // would dismiss it on the first mouse move. Setting this directly (no
        // deferred runloop turn needed - unlike the old NSPopover, we own the
        // panel synchronously) keeps the panel on the active Space instead.
        panel.collectionBehavior.insert(.canJoinAllSpaces)
        panel.collectionBehavior.insert(.fullScreenAuxiliary)

        hosting.view.layoutSubtreeIfNeeded()
        let fitSize = hosting.view.fittingSize
        let size = NSSize(width: max(fitSize.width, 340), height: max(fitSize.height, 1))
        panel.setContentSize(size)

        let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let gap: CGFloat = 6
        panel.setFrameOrigin(NSPoint(
            x: buttonFrameInScreen.maxX - size.width,
            y: buttonFrameInScreen.minY - size.height - gap
        ))

        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        startPopoverDismissMonitors()
    }

    func showDashboard() {
        dismissPopover()

        // Promote to a regular app (Dock icon + app menu) while the dashboard
        // is open so it feels like a real window; windowShouldClose drops back
        // to .accessory (menu-bar-only) when the window is closed, so the Dock
        // icon is only present while the window actually is.
        NSApp.setActivationPolicy(.regular)

        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let appView = MainAppView()
            .environmentObject(usageStore)
            .environmentObject(settingsStore)
            .environmentObject(vendorStatusStore)

        let isOnboarding = !settingsStore.hasCompletedOnboarding
        let onboardingSize = NSSize(
            width: DS.Layout.onboardingWindow.width,
            height: DS.Layout.onboardingWindow.height
        )
        let size = isOnboarding ? onboardingSize : NSSize(width: 940, height: 700)
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        if !isOnboarding { styleMask.insert(.resizable) }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Keep drag limited to the titlebar area in dashboard mode. With
        // this on for the dashboard, clicking + holding on any padding /
        // empty space in the sidebar, the settings panels, or the popover
        // editor would drag the whole window by accident. For onboarding,
        // the user has a fixed-size panel without a sidebar - we let them
        // drag from anywhere on the background so the window doesn't feel
        // stuck behind the titlebar strip.
        window.isMovableByWindowBackground = isOnboarding
        window.delegate = self
        // Dark-first: the app's fixed-dark DS.Pastel surfaces pair with adaptive
        // .primary/.secondary text, which would read as black-on-black under a
        // light system appearance. Pin the window to dark so text stays legible.
        window.appearance = NSAppearance(named: .darkAqua)

        let hostingController = NSHostingController(rootView: appView)
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.setContentSize(size)
        window.center()

        if isOnboarding {
            window.minSize = size
            window.maxSize = size
        } else {
            window.minSize = Self.dashboardMinSize
            window.contentMinSize = Self.dashboardMinSize
            window.setFrameAutosaveName("RaiUsageMain")
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.dashboardWindow = window
        observeOnboardingCompletion()
    }

    /// Observe onboarding state in BOTH directions so the NSWindow stays
    /// in sync with what the SwiftUI view is rendering. Without this, the
    /// "replay onboarding" path leaves the window at the dashboard size
    /// (940x700) while the SwiftUI body switches to onboardingContent,
    /// producing the empty-margin ghost effect.
    private func observeOnboardingCompletion() {
        settingsStore.$hasCompletedOnboarding
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] completed in
                if completed {
                    self?.transitionToMainWindow()
                } else {
                    self?.transitionToOnboardingWindow()
                }
            }
            .store(in: &cancellables)
    }

    private func transitionToMainWindow() {
        guard let window = dashboardWindow else { return }
        window.styleMask.insert(.resizable)
        window.contentMinSize = NSSize(width: 600, height: 440)
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.minSize = NSSize(width: 600, height: 440)
        window.isMovableByWindowBackground = false
        window.setFrameAutosaveName("RaiUsageMain")
        let mainSize = NSSize(width: 940, height: 700)
        window.setContentSize(mainSize)
        window.center()
    }

    /// Inverse of `transitionToMainWindow`: shrink the dashboard window
    /// back to the onboarding size when the user resets onboarding from
    /// Settings.
    private func transitionToOnboardingWindow() {
        guard let window = dashboardWindow else { return }
        window.styleMask.remove(.resizable)
        let onboardingSize = NSSize(
            width: DS.Layout.onboardingWindow.width,
            height: DS.Layout.onboardingWindow.height
        )
        window.contentMinSize = onboardingSize
        window.contentMaxSize = onboardingSize
        window.minSize = onboardingSize
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("")
        window.setContentSize(onboardingSize)
        window.center()
    }

    // MARK: - Event Monitor

    private func startPopoverDismissMonitors() {
        // Click into another app closes the popover.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissPopover()
        }
        // Escape closes it. A key event is delivered to our own app, so it never
        // reaches the global monitor above - a local monitor is required.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // 53 = Escape
            self?.dismissPopover()
            return nil
        }
        // App deactivation (Cmd-Tab, clicking another app) and Space changes
        // close it too, restoring the dismissal .transient gave us for free
        // before we switched to .applicationDefined for the fullscreen fix.
        appDeactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismissPopover()
        }
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismissPopover()
        }
    }

    /// Close the popover and tear down every dismissal monitor/observer.
    private func dismissPopover() {
        popoverPanel?.orderOut(nil)
        popoverHostingController?.view.removeFromSuperview()
        popoverHostingController = nil
        stopPopoverDismissMonitors()
    }

    private func stopPopoverDismissMonitors() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let observer = appDeactivateObserver {
            NotificationCenter.default.removeObserver(observer)
            appDeactivateObserver = nil
        }
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
    }
}

// MARK: - NSWindowDelegate

extension StatusBarController: NSWindowDelegate {
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            if !self.settingsStore.hasCompletedOnboarding {
                // User closed during onboarding: quit rather than sit
                // half-onboarded and unconnected in the menu bar.
                NSApp.terminate(nil)
                return
            }
            sender.contentViewController = nil
            sender.orderOut(nil)
            self.dashboardWindow = nil
            // Closing the dashboard (not quitting) returns the app to
            // menu-bar-only: drop the Dock icon + app menu.
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    /// Hard-clamp the resize so AppKit can't honor a frame smaller than our
    /// declared min, even if `setFrameAutosaveName` restored a stale frame
    /// or the user drags the resize grip past the floor. Belt-and-braces
    /// for the `minSize` / `contentMinSize` properties.
    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, StatusBarController.dashboardMinSize.width),
            height: max(frameSize.height, StatusBarController.dashboardMinSize.height)
        )
    }
}

// MARK: - Notification

extension Notification.Name {
    static let openDashboard = Notification.Name("openDashboard")
    static let navigateToSection = Notification.Name("navigateToSection")
}
