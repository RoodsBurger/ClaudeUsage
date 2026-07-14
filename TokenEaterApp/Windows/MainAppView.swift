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
                // The AppKit-hosted NSWindow (see StatusBarController.showDashboard)
                // has a hidden native title, so a `.toolbar` item never docks to the
                // real trailing edge - it renders bunched next to the sidebar toggle
                // instead. A dedicated top-bar strip, reserved above the detail
                // content via safeAreaInset, is what actually lands the button at
                // the trailing edge in every section without overlapping each
                // page's own header row.
                .safeAreaInset(edge: .top, spacing: 0) { topBar }
        }
        .background(DS.Pastel.base)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { notification in
            guard let payload = notification.userInfo?["section"] as? String,
                  let target = NavigationTarget.parse(payload) else { return }
            selection = target.item
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(String(localized: "menubar.quit"))
        }
        .padding(.trailing, DS.Spacing.md)
        .padding(.top, 8)
        .padding(.bottom, 4)
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
