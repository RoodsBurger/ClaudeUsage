import SwiftUI

/// Settings space -> hosts the secondary sidebar (`SettingsSubSidebar`) and
/// dispatches to the correct configuration screen based on `selection`. Each
/// screen lives in its own file -> this view is just the router.
struct SettingsRootView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    @Binding var selection: SettingsSection

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            SettingsSubSidebar(selection: $selection)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .fill(DS.Palette.bgElevated.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.card)
                                .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
                        )
                )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:
            scrolling { SettingsSectionView(initialStatusInterval: settingsStore.statusPollInterval) }
        case .menuBar:
            MenuBarSectionView()
        case .popover:
            PopoverSectionView()
        case .pacing:
            scrolling {
                PacingSectionView(
                    initialWarning: settingsStore.warningThreshold,
                    initialCritical: settingsStore.criticalThreshold,
                    initialMargin: settingsStore.pacingMargin
                )
            }
        case .notifications:
            scrolling { NotificationsSectionView() }
        }
    }

    @ViewBuilder
    private func scrolling<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}
