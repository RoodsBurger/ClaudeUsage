import SwiftUI

struct MainAppView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var selection: SidebarItem = .monitoring

    // Hoisted from the child views so each store's cache outlives sidebar
    // navigation; re-selecting a space hits warm data instead of triggering
    // a fresh load.
    @StateObject private var historyStore = HistoryStore()
    @StateObject private var insightsStore = MonitoringInsightsStore()

    var body: some View {
        Group {
            if settingsStore.hasCompletedOnboarding {
                mainContent
            } else {
                onboardingContent
            }
        }
    }

    // MARK: - Main

    private var mainContent: some View {
        NavigationSplitView {
            SidebarNav(selection: $selection)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The window hides its title bar (fullSizeContentView), but
                // NavigationSplitView still reserves a toolbar strip above the
                // detail pane. Pad the content a comfortable 12pt first, THEN
                // ignore the safe area (outermost) so the reserved strip is
                // reclaimed - reversed, the padding re-enters the safe area
                // and the oversized strip comes back.
                .padding(.top, DS.Spacing.sm)
                .ignoresSafeArea(.container, edges: .top)
        }
        .background(DS.Pastel.base)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { notification in
            guard let payload = notification.userInfo?["section"] as? String,
                  let target = NavigationTarget.parse(payload) else { return }
            selection = target.item
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .monitoring:
            MonitoringView(insightsStore: insightsStore)
        case .history:
            HistoryView(store: historyStore)
        case .settings(let section):
            settingsDetail(for: section)
        }
    }

    /// Routes a `SettingsSection` to its configuration screen. Folded in from
    /// the deleted `SettingsRootView` -> each screen still lives in its own
    /// file, this is just the switch.
    @ViewBuilder
    private func settingsDetail(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            SettingsSectionView()
        case .menuBar:
            MenuBarSectionView()
        case .popover:
            PopoverSectionView()
        case .pacing:
            PacingSectionView(
                initialWarning: settingsStore.warningThreshold,
                initialCritical: settingsStore.criticalThreshold,
                initialMargin: settingsStore.pacingMargin
            )
        case .notifications:
            NotificationsSectionView()
        }
    }

    // MARK: - Onboarding

    private var onboardingContent: some View {
        OnboardingHeroView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
